import AVFoundation
import Speech

public struct AudioTrackInfo: Identifiable, Sendable, Equatable {
    public let id: Int32
    public let label: String
}

public struct MediaInfo: Sendable {
    public let duration: Double
    public let tracks: [AudioTrackInfo]
    public static func inspect(_ url: URL) async throws -> MediaInfo {
        guard url.pathExtension.lowercased() == "mp4" else {
            throw TranscriberError.message("Choose an MP4 video.")
        }
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw TranscriberError.message("This video has no readable duration.") }
        guard try await !asset.load(.hasProtectedContent) else { throw TranscriberError.message("Protected videos cannot be transcribed.") }
        let audio = try await asset.loadTracks(withMediaType: .audio)
        guard !audio.isEmpty else { throw TranscriberError.message("This video has no audio track.") }
        var tracks: [AudioTrackInfo] = []
        for (index, track) in audio.enumerated() {
            let extended = try await track.load(.extendedLanguageTag)
            let code = try await track.load(.languageCode)
            let language = extended ?? code
            tracks.append(AudioTrackInfo(id: track.trackID,
                label: "Audio \(index + 1)" + (language.map { " (\(TextPolicy.clean($0)))" } ?? "")))
        }
        return MediaInfo(duration: duration, tracks: tracks)
    }
}

/// A pull-based sequence: the analyzer requests each buffer before another sample is decoded.
public struct AudioInputSequence: AsyncSequence, Sendable {
    public typealias Element = AnalyzerInput
    public let reader: AudioReader
    public init(reader: AudioReader) { self.reader = reader }
    public func makeAsyncIterator() -> Iterator { Iterator(reader: reader) }
    public struct Iterator: AsyncIteratorProtocol {
        let reader: AudioReader
        public mutating func next() async throws -> AnalyzerInput? { try await reader.next() }
    }
}

/// AVFoundation objects and resampling state are confined to this actor.
public actor AudioReader {
    private let assetReader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    private let format: AVAudioFormat
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private var currentInput: AVAudioPCMBuffer?
    private var pendingInput: AVAudioPCMBuffer?
    private var pendingTime: Double?
    private var previousSourceEnd: Double?
    private var cursor: Int64 = 0
    private var eof = false
    private var drainingGap = false
    private var finished = false
    private var cancelled = false
    public private(set) var decodedThrough: Double = 0
    public private(set) var outputFrames: Int64 = 0

    public init(url: URL, trackID: Int32, format: AVAudioFormat) async throws {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first(where: { $0.trackID == trackID }) else {
            throw TranscriberError.message("The selected audio track is no longer available.")
        }
        self.format = format
        assetReader = try AVAssetReader(asset: asset)
        output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false
        ])
        output.alwaysCopiesSampleData = false
        guard assetReader.canAdd(output) else { throw TranscriberError.message("This audio format cannot be decoded.") }
        assetReader.add(output)
        guard assetReader.startReading() else { throw assetReader.error ?? TranscriberError.message("Could not read the video's audio.") }
    }

    public func cancel() { cancelled = true; assetReader.cancelReading(); currentInput = nil; pendingInput = nil }

    public func next() throws -> AnalyzerInput? {
        try Task.checkCancellation()
        guard !cancelled else { throw CancellationError() }
        guard !finished else { return nil }
        while true {
            try Task.checkCancellation()
            if currentInput == nil && !eof && !drainingGap {
                if let pendingInput, let pendingTime {
                    self.pendingInput = nil; self.pendingTime = nil
                    try install(pendingInput, at: pendingTime)
                } else if let sample = output.copyNextSampleBuffer() {
                    let pcm = try Self.copyPCM(sample)
                    let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                    guard pts.isFinite, pts >= -0.001 else { throw TranscriberError.message("The audio contains invalid timestamps.") }
                    let time = max(0, pts)
                    let gap = previousSourceEnd.map { time - $0 } ?? 0
                    guard gap >= -0.05 else { throw TranscriberError.message("The audio timeline overlaps. Export a new MP4 and try again.") }
                    previousSourceEnd = time + Double(pcm.frameLength) / pcm.format.sampleRate
                    decodedThrough = previousSourceEnd ?? time
                    if converter != nil && (gap > 0.05 || inputFormat != pcm.format) {
                        pendingInput = pcm; pendingTime = time; drainingGap = true
                    } else {
                        try install(pcm, at: time)
                    }
                } else {
                    if assetReader.status == .failed { throw assetReader.error ?? TranscriberError.message("Audio decoding failed.") }
                    if assetReader.status == .cancelled { throw CancellationError() }
                    eof = true
                }
            }
            guard let converter else { finished = true; return nil }
            guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192) else {
                throw TranscriberError.message("Could not allocate an audio conversion buffer.")
            }
            let input = ConversionInput(buffer: currentInput, ending: eof || drainingGap)
            var error: NSError?
            let status = converter.convert(to: converted, error: &error) { _, state in input.supply(state) }
            if input.delivered { currentInput = nil }
            if let error { throw error }
            guard status != .error else { throw TranscriberError.message("Audio conversion failed.") }
            if status == .endOfStream {
                if drainingGap {
                    self.converter = nil; inputFormat = nil; drainingGap = false
                } else { finished = true }
            }
            if converted.frameLength > 0 {
                let time = CMTime(value: cursor, timescale: CMTimeScale(format.sampleRate))
                cursor += Int64(converted.frameLength); outputFrames += Int64(converted.frameLength)
                return AnalyzerInput(buffer: converted, bufferStartTime: time)
            }
            if finished { return nil }
        }
    }

    private func install(_ pcm: AVAudioPCMBuffer, at time: Double) throws {
        if converter == nil {
            converter = AVAudioConverter(from: pcm.format, to: format)
            inputFormat = pcm.format
            cursor = Int64((time * format.sampleRate).rounded())
        }
        guard converter != nil else { throw TranscriberError.message("This audio cannot be converted for speech recognition.") }
        currentInput = pcm
    }

    private static func copyPCM(_ sample: CMSampleBuffer) throws -> AVAudioPCMBuffer {
        guard let description = CMSampleBufferGetFormatDescription(sample) else {
            throw TranscriberError.message("The audio sample has no format description.")
        }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        let count = CMSampleBufferGetNumSamples(sample)
        guard count > 0, count <= 1_048_576,
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else {
            throw TranscriberError.message("The audio sample has an unsupported size.")
        }
        pcm.frameLength = pcm.frameCapacity
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(count), into: pcm.mutableAudioBufferList)
        guard status == noErr else { throw TranscriberError.message("Could not decode an audio sample (\(status)).") }
        return pcm
    }
}

/// The converter calls this box synchronously. It never escapes one conversion call.
private final class ConversionInput: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer?
    let ending: Bool
    var delivered = false
    init(buffer: AVAudioPCMBuffer?, ending: Bool) { self.buffer = buffer; self.ending = ending }
    func supply(_ state: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        if !delivered, let buffer { delivered = true; state.pointee = .haveData; return buffer }
        state.pointee = ending ? .endOfStream : .noDataNow
        return nil
    }
}
