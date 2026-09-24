import AVFoundation
import Speech

public enum TranscriptionEvent: Sendable {
    case phase(String)
    case download(Double)
    case progress(Double)
    case passage(Passage)
}

public actor TranscriptionService {
    private var busy = false
    public init() {}

    public func transcribe(url: URL, trackID: Int32, duration: Double,
                           report: @escaping @Sendable (TranscriptionEvent) async -> Void) async throws {
        guard !busy else { throw TranscriberError.message("Wait for the previous transcription to finish cancelling.") }
        busy = true
        defer { busy = false }
        try Task.checkCancellation()
        await report(.phase("Preparing English recognition"))
        guard SpeechTranscriber.isAvailable else {
            throw TranscriberError.message("On-device speech recognition is unavailable on this Mac. An Apple silicon Mac running macOS 26 or later is required.")
        }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en_US")) else {
            throw TranscriberError.message("English recognition is unavailable. Check your macOS language and speech settings.")
        }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
        try await AssetInventory.reserve(locale: locale)
        // A single English reservation is intentionally retained for subsequent offline launches.
        let status = await AssetInventory.status(forModules: [transcriber])
        if status != .installed, let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            await report(.phase("Downloading the English speech model"))
            let progress = Task {
                while !Task.isCancelled {
                    await report(.download(request.progress.fractionCompleted))
                    try await Task.sleep(for: .milliseconds(250))
                }
            }
            defer { progress.cancel() }
            try await request.downloadAndInstall()
        }
        try Task.checkCancellation()
        let analyzer = SpeechAnalyzer(modules: [transcriber], options: .init(priority: .userInitiated, modelRetention: .whileInUse))
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TranscriberError.message("Could not prepare a compatible speech audio format.")
        }
        let reader = try await AudioReader(url: url, trackID: trackID, format: format)
        do {
            try await withTaskCancellationHandler {
                try await analyzer.prepareToAnalyze(in: format)
                try Task.checkCancellation()
                await report(.phase("Transcribing on this Mac"))
                let progress = Task {
                    while !Task.isCancelled {
                        let through = await reader.decodedThrough
                        await report(.progress(min(0.99, max(0, through / max(1, duration)))))
                        try await Task.sleep(for: .milliseconds(300))
                    }
                }
                defer { progress.cancel() }
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        for try await result in transcriber.results {
                            try Task.checkCancellation()
                            guard result.isFinal else { continue }
                            let passage = Self.passage(from: result)
                            if !passage.text.isEmpty { await report(.passage(passage)) }
                        }
                    }
                    group.addTask {
                        if let last = try await analyzer.analyzeSequence(AudioInputSequence(reader: reader)) {
                            await report(.phase("Finalizing transcript"))
                            try await analyzer.finalizeAndFinish(through: last)
                        } else { await analyzer.cancelAndFinishNow() }
                    }
                    do { while try await group.next() != nil {} }
                    catch {
                        group.cancelAll()
                        await reader.cancel()
                        await analyzer.cancelAndFinishNow()
                        throw error
                    }
                }
                try Task.checkCancellation()
            } onCancel: {
                Task { await reader.cancel(); await analyzer.cancelAndFinishNow() }
            }
        } catch {
            await reader.cancel(); await analyzer.cancelAndFinishNow()
            throw error
        }
        await reader.cancel()
        await report(.progress(1))
    }

    private static func passage(from result: SpeechTranscriber.Result) -> Passage {
        var words: [TimedWord] = []
        var prefix = ""
        for run in result.text.runs {
            let text = String(result.text[run.range].characters)
            if let range = run.audioTimeRange, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                words.append(TimedWord(text: prefix + text, start: range.start.seconds, end: range.end.seconds))
                prefix = ""
            } else if !words.isEmpty { words[words.count - 1].text += TextPolicy.clean(text) }
            else { prefix += TextPolicy.clean(text) }
        }
        return Passage(start: result.range.start.seconds, end: result.range.end.seconds,
                       text: String(result.text.characters), words: words)
    }
}
