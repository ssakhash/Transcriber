import AVFoundation
import Foundation
import Speech
import TranscriberKit

@main struct MediaProbe {
    static func main() async {
        do { try await run() }
        catch {
            FileHandle.standardError.write(Data((TextPolicy.clean(error.localizedDescription) + "\n").utf8))
            exit(1)
        }
    }
    static func run() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else { throw TranscriberError.message("Usage: MediaProbe capabilities | inspect <mp4> | decode <mp4> | transcribe <mp4> <text-output> | generate <mp4> <speech-aiff> <seconds> [delay] [tracks]") }
        if command == "capabilities" {
            print("Speech available: \(SpeechTranscriber.isAvailable)")
            print("Installed English: \(await SpeechTranscriber.installedLocales.contains { $0.language.languageCode?.identifier == "en" })")
            return
        }
        guard arguments.count > 1 else { throw TranscriberError.message("A file path is required.") }
        let url = URL(fileURLWithPath: arguments[1])
        if command == "storage" {
            let values = try url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeNameKey])
            guard let capacity = values.volumeTotalCapacity, capacity < 64 * 1024 * 1024,
                  values.volumeName == "TranscriberStorageTest" else {
                throw TranscriberError.message("Storage validation requires the dedicated small test disk image.")
            }
            let directory = url.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let sessionURL = directory.appendingPathComponent("session.json")
            let store = SessionStore(url: sessionURL)
            try await store.save(TranscriptSession(sourceName: "preserve.mp4"))
            let original = try Data(contentsOf: sessionURL)
            let filler = directory.appendingPathComponent("filler")
            FileManager.default.createFile(atPath: filler.path, contents: nil)
            let handle = try FileHandle(forWritingTo: filler)
            defer { try? handle.close() }
            let block = Data(repeating: 0x55, count: 4096)
            var filled = false
            for _ in 0..<(capacity / block.count + 1) {
                do { try handle.write(contentsOf: block) }
                catch {
                    let failure = error as NSError
                    guard failure.domain == NSPOSIXErrorDomain && failure.code == Int(ENOSPC) || failure.code == NSFileWriteOutOfSpaceError else { throw error }
                    filled = true; break
                }
            }
            guard filled else { throw TranscriberError.message("The dedicated volume did not report a full disk.") }
            var replacement = TranscriptSession(sourceName: "replacement.mp4")
            replacement.append(Passage(start: 0, end: 1, text: String(repeating: "Test ", count: 100_000)))
            do {
                try await store.save(replacement)
                throw TranscriberError.message("A full-volume save unexpectedly succeeded.")
            } catch {
                guard try Data(contentsOf: sessionURL) == original else { throw TranscriberError.message("The existing session changed after a failed write.") }
            }
            try handle.close()
            try FileManager.default.removeItem(at: filler)
            try await store.save(replacement)
            guard try await store.load()?.sourceName == replacement.sourceName else { throw TranscriberError.message("Saving did not recover after space became available.") }
            print("Full-volume write preserved the original session; save recovered after freeing test space")
            return
        }
        if command == "generate", arguments.count >= 4 {
            try await generate(url: url, speech: URL(fileURLWithPath: arguments[2]), duration: Double(arguments[3]) ?? 8,
                               delay: arguments.count > 4 ? Double(arguments[4]) ?? 0 : 0,
                               tracks: arguments.count > 5 ? Int(arguments[5]) ?? 1 : 1,
                               silent: arguments.count > 6 && arguments[6] == "silent")
            print("Generated fixture")
            return
        }
        let info = try await MediaInfo.inspect(url)
        print("Duration: \(info.duration); audio tracks: \(info.tracks.count)")
        guard let track = info.tracks.first else { return }
        if command == "inspect" { return }
        if command == "decode" {
            let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
            let reader = try await AudioReader(url: url, trackID: track.id, format: format)
            var count = 0, first: Double?, end: Double = 0, firstAudible: Double?
            for try await input in AudioInputSequence(reader: reader) {
                let start = input.bufferStartTime?.seconds ?? 0
                guard count == 0 || start >= end - 0.001 else { throw TranscriberError.message("Overlapping output audio.") }
                first = first ?? start
                if firstAudible == nil, let samples = input.buffer.floatChannelData?[0],
                   let frame = (0..<Int(input.buffer.frameLength)).first(where: { abs(samples[$0]) > 0.02 }) {
                    firstAudible = start + Double(frame) / format.sampleRate
                }
                end = start + Double(input.buffer.frameLength) / format.sampleRate
                count += 1
            }
            print("Buffers: \(count); first: \(first ?? -1); end: \(end); frames: \(await reader.outputFrames); audible: \(firstAudible ?? -1)")
            return
        }
        if command == "transcribe", arguments.count > 2 {
            let collector = Collector(source: url.lastPathComponent, duration: info.duration, trackID: track.id)
            let start = Date()
            try await TranscriptionService().transcribe(url: url, trackID: track.id, duration: info.duration) { event in
                await collector.receive(event)
            }
            let result = await collector.complete()
            try result.exportText().write(to: URL(fileURLWithPath: arguments[2]), atomically: true, encoding: .utf8)
            if arguments.contains("--session") {
                try JSONEncoder().encode(result).write(to: URL(fileURLWithPath: arguments[2]).appendingPathExtension("json"), options: .atomic)
            }
            print("Passages: \(result.passages.count); first: \(result.passages.first?.start ?? -1); last: \(result.passages.last?.end ?? -1); elapsed: \(Date().timeIntervalSince(start))")
            return
        }
        if command == "cancel-restart", arguments.count > 2 {
            let service = TranscriptionService()
            let collector = Collector(source: url.lastPathComponent, duration: info.duration, trackID: track.id)
            let task = Task {
                try await service.transcribe(url: url, trackID: track.id, duration: info.duration) { await collector.receive($0) }
            }
            for _ in 0..<1000 {
                if await collector.count > 0 { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            task.cancel()
            let result = await task.result
            guard case .failure = result, await collector.count > 0 else {
                throw TranscriberError.message("Cancellation check did not preserve partial passages.")
            }
            let retained = await collector.count
            try await Task.sleep(for: .milliseconds(100))
            guard await collector.count == retained else { throw TranscriberError.message("Results arrived after cancellation completed.") }
            let next = URL(fileURLWithPath: arguments[2])
            let nextInfo = try await MediaInfo.inspect(next)
            let nextCollector = Collector(source: next.lastPathComponent, duration: nextInfo.duration, trackID: nextInfo.tracks[0].id)
            try await service.transcribe(url: next, trackID: nextInfo.tracks[0].id, duration: nextInfo.duration) { await nextCollector.receive($0) }
            guard await nextCollector.count > 0 else { throw TranscriberError.message("Restart produced no passages.") }
            print("Cancellation preserved \(retained) passages; immediate restart passed")
            return
        }
        throw TranscriberError.message("Unknown command or missing arguments.")
    }

    static func generate(url: URL, speech: URL, duration: Double, delay: Double, tracks: Int, silent: Bool = false) async throws {
        guard duration > 0, duration <= 12000, delay >= 0, delay < duration, (0...3).contains(tracks) else {
            throw TranscriberError.message("Invalid fixture parameters.")
        }
        let file = try AVAudioFile(forReading: speech, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard file.length < 10_000_000, let voice = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw TranscriberError.message("Use a short speech fixture.")
        }
        try file.read(into: voice)
        guard let samples = voice.floatChannelData?[0] else { throw TranscriberError.message("No PCM fixture data.") }
        let sampleRate = file.processingFormat.sampleRate
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 32, AVVideoHeightKey: 32])
        writer.add(video)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 32, kCVPixelBufferHeightKey as String: 32])
        var inputs: [AVAssetWriterInput] = []
        for _ in 0..<tracks {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 64000])
            writer.add(input); inputs.append(input)
        }
        guard writer.startWriting() else { throw writer.error! }
        writer.startSession(atSourceTime: .zero)
        var pixel: CVPixelBuffer?
        CVPixelBufferCreate(nil, 32, 32, kCVPixelFormatType_32ARGB, nil, &pixel)
        guard let pixel else { throw TranscriberError.message("Could not allocate fixture frame.") }
        CVPixelBufferLockBaseAddress(pixel, [])
        memset(CVPixelBufferGetBaseAddress(pixel), 32, CVPixelBufferGetDataSize(pixel))
        CVPixelBufferUnlockBaseAddress(pixel, [])
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: true)!
        var audioFrame: Int64 = Int64(delay * sampleRate)
        var videoFrame: Int64 = 0
        let total = Int64(duration * sampleRate)
        let period = Int64(max(30, Double(voice.frameLength) / sampleRate + 2) * sampleRate)
        while videoFrame <= Int64(duration) || (!inputs.isEmpty && audioFrame < total) {
            try Task.checkCancellation()
            var advanced = false
            if videoFrame <= Int64(duration), video.isReadyForMoreMediaData {
                guard adaptor.append(pixel, withPresentationTime: CMTime(value: videoFrame, timescale: 1)) else { throw writer.error! }
                videoFrame += 1; advanced = true
                if videoFrame > Int64(duration) { video.markAsFinished() }
            }
            if !inputs.isEmpty, audioFrame < total, inputs.allSatisfy(\.isReadyForMoreMediaData) {
                let count = AVAudioFrameCount(min(1024, total - audioFrame))
                let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
                pcm.frameLength = count
                let data = pcm.floatChannelData![0]
                for frame in 0..<Int(count) {
                    let position = audioFrame + Int64(frame) - Int64(delay * sampleRate)
                    let finalStart = total - Int64(voice.frameLength) - Int64(delay * sampleRate)
                    let offset = position >= finalStart ? position - finalStart : position % period
                    let sample: Float = !silent && offset >= 0 && offset < voice.frameLength ? samples[Int(offset)] : 0
                    data[frame * 2] = sample; data[frame * 2 + 1] = sample
                }
                var sample: CMSampleBuffer?
                var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: Int32(sampleRate)), presentationTimeStamp: CMTime(value: audioFrame, timescale: Int32(sampleRate)), decodeTimeStamp: .invalid)
                let status = CMSampleBufferCreate(allocator: nil, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil, refcon: nil, formatDescription: format.formatDescription, sampleCount: Int(count), sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample)
                guard status == noErr, let sample,
                      CMSampleBufferSetDataBufferFromAudioBufferList(sample, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, bufferList: pcm.audioBufferList) == noErr else { throw TranscriberError.message("Could not construct fixture audio.") }
                CMSampleBufferSetDataReady(sample)
                for input in inputs { guard input.append(sample) else { throw writer.error! } }
                audioFrame += Int64(count); advanced = true
                if audioFrame >= total { inputs.forEach { $0.markAsFinished() } }
            }
            if !advanced {
                guard writer.status == .writing else { throw writer.error ?? TranscriberError.message("Fixture writer stopped.") }
                try await Task.sleep(for: .milliseconds(1))
            }
        }
        writer.endSession(atSourceTime: CMTime(seconds: duration, preferredTimescale: 600))
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? TranscriberError.message("Fixture generation failed.") }
    }
}

private actor Collector {
    var session: TranscriptSession
    var count: Int { session.passages.count }
    init(source: String, duration: Double, trackID: Int32) { session = TranscriptSession(sourceName: source, duration: duration, trackID: trackID) }
    func receive(_ event: TranscriptionEvent) {
        switch event {
        case .passage(let passage): session.append(passage)
        case .phase(let phase): print(TextPolicy.clean(phase))
        default: break
        }
    }
    func complete() -> TranscriptSession { session.state = .complete; return session }
}
