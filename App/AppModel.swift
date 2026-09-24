import AppKit
import AVKit
import Observation
import TranscriberKit
import UniformTypeIdentifiers

@MainActor @Observable final class AppModel {
    var session = TranscriptSession()
    var tracks: [AudioTrackInfo] = []
    var player = AVPlayer()
    var sourceURL: URL?
    var loading = false
    var busy = false
    var cancelling = false
    var phase = "Ready when you are"
    var progress: Double = 0
    var download: Double?
    var notice: String?
    var noticeIsError = false
    var saveError: String?
    var recoveryRequired = false
    var suggestions: [NameSuggestion] = []
    var activePassage: UUID?
    var splitPassage: UUID?
    var playbackTime: Double = 0
    var wordCount = 0
    var isPreview: Bool
    @ObservationIgnored private let service = TranscriptionService()
    @ObservationIgnored private let store: SessionStore
    @ObservationIgnored private var job: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var suggestionTask: Task<Void, Never>?
    @ObservationIgnored private var gate = JobGate()
    @ObservationIgnored private var accessURL: URL?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var sleepObserver: NSObjectProtocol?
    @ObservationIgnored private var activity: NSObjectProtocol?

    init(preview: Bool = false) {
        isPreview = preview
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Transcriber", isDirectory: true)
        store = SessionStore(url: directory.appendingPathComponent("session.json"))
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.playbackTime = time.seconds.isFinite ? time.seconds : 0
                self.activePassage = self.session.passages.first(where: { $0.start <= self.playbackTime && $0.end > self.playbackTime })?.id
            }
        }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.busy else { return }
                self.cancel()
                self.notify("Transcription stopped for sleep. Completed passages are saved; restart when ready.")
            }
        }
        if preview { makePreview() }
        else { loading = true; Task { await restore() } }
    }

    var hasVideo: Bool { sourceURL != nil }
    var canExport: Bool { !session.passages.isEmpty && !busy && !loading }
    var editorLocked: Bool { busy || loading || recoveryRequired }

    func notify(_ message: String, error: Bool = false) {
        notice = TextPolicy.clean(message); noticeIsError = error
    }

    func chooseVideo(relink: Bool = false) {
        guard !busy, !loading, !recoveryRequired else { return }
        let panel = NSOpenPanel()
        panel.title = relink ? "Locate the original video" : "Open an MP4 video"
        panel.allowedContentTypes = [UTType(filenameExtension: "mp4")!]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await importVideo(url, relink: relink) }
    }

    func importVideo(_ url: URL, relink: Bool = false) async {
        guard !busy, !loading, !recoveryRequired else { return }
        loading = true
        defer { loading = false }
        let accessed = url.startAccessingSecurityScopedResource()
        var keepAccess = false
        defer { if accessed && !keepAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let info = try await MediaInfo.inspect(url)
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let chosenTrack = relink ? session.trackID : info.tracks[0].id
            let playback = try await makePlayback(url: url, trackID: chosenTrack)
            if relink {
                guard abs(info.duration - session.duration) < 0.25,
                      session.sourceSize == nil || session.sourceSize == values.fileSize.map(Int64.init),
                      info.tracks.contains(where: { $0.id == session.trackID }) else {
                    throw TranscriberError.message("This file does not match the saved video's duration, size, or audio track. Open it as a new video instead.")
                }
            } else {
                guard confirmReplacement() else { return }
            }
            let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            if !relink {
                session = TranscriptSession(sourceName: url.lastPathComponent, duration: info.duration, trackID: info.tracks[0].id)
                suggestions = []; wordCount = 0
            }
            session.bookmark = bookmark
            session.sourceSize = values.fileSize.map(Int64.init); session.sourceModified = values.contentModificationDate
            releaseVideo()
            accessURL = accessed ? url : nil; keepAccess = accessed
            sourceURL = url; tracks = info.tracks
            player.replaceCurrentItem(with: playback)
            phase = session.state == .complete ? "Transcript restored" : "Ready to transcribe"
            notice = nil
            await saveNow()
        } catch { notify(error.localizedDescription, error: true) }
    }

    func setTrack(_ trackID: Int32) {
        guard !editorLocked, session.passages.isEmpty, let sourceURL else { return }
        loading = true
        Task {
            defer { loading = false }
            do {
                let playback = try await makePlayback(url: sourceURL, trackID: trackID)
                player.pause(); player.replaceCurrentItem(with: playback)
                session.trackID = trackID; scheduleSave()
            } catch { notify(error.localizedDescription, error: true) }
        }
    }

    // A composition selects the exact transcription track for preview without changing the source.
    private func makePlayback(url: URL, trackID: Int32) async throws -> AVPlayerItem {
        let asset = AVURLAsset(url: url)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        guard let selected = audio.first(where: { $0.trackID == trackID }) else {
            throw TranscriberError.message("The selected audio track is no longer available.")
        }
        guard audio.count > 1 else { return AVPlayerItem(asset: asset) }
        let composition = AVMutableComposition()
        let videos = try await asset.loadTracks(withMediaType: .video)
        for original in videos + [selected] {
            guard let destination = composition.addMutableTrack(withMediaType: original.mediaType, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw TranscriberError.message("Could not prepare video playback.")
            }
            let range = try await original.load(.timeRange)
            try destination.insertTimeRange(range, of: original, at: range.start)
            if original.mediaType == .video { destination.preferredTransform = try await original.load(.preferredTransform) }
        }
        return AVPlayerItem(asset: composition)
    }

    func transcribe() {
        guard !busy, !loading, !recoveryRequired, let url = sourceURL else { return }
        if !session.passages.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Replace the current transcript?"
            alert.informativeText = "Restarting transcribes the entire video and replaces its passages and edits. Save a text copy first if you want to keep them."
            alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Restart")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        session.passages = []; session.speakers = []; session.state = .transcribing; session.changed()
        suggestions = []; wordCount = 0; notice = nil; progress = 0; download = nil
        busy = true; cancelling = false; player.pause()
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Transcribing the selected video")
        let id = gate.begin()
        let trackID = session.trackID, duration = session.duration
        scheduleSave()
        job = Task { [weak self, service] in
            guard let self else { return }
            do {
                try await service.transcribe(url: url, trackID: trackID, duration: duration) { [weak self] event in
                    await self?.receive(event, generation: id)
                }
                guard self.gate.accepts(id) else { return }
                self.session.state = .complete
                self.phase = self.session.passages.isEmpty ? "No speech detected" : "Transcription complete"
                if self.session.passages.isEmpty { self.notify("No English speech was detected in this audio track. Try a different track if available.") }
            } catch {
                guard self.gate.accepts(id) else { return }
                if Task.isCancelled || error is CancellationError {
                    self.session.state = .interrupted; self.phase = "Cancelled. Completed passages kept."
                } else {
                    self.session.state = .failed; self.phase = "Transcription stopped"
                    self.notify(error.localizedDescription, error: true)
                }
            }
            self.session.changed(); self.gate.invalidate()
            self.busy = false; self.cancelling = false; self.download = nil; self.job = nil
            if let activity = self.activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
            self.updateSuggestions()
            await self.saveNow()
        }
    }

    private func receive(_ event: TranscriptionEvent, generation: UUID) {
        guard gate.accepts(generation), !cancelling else { return }
        switch event {
        case .phase(let text): phase = TextPolicy.clean(text); download = nil
        case .download(let value): download = value
        case .progress(let value): progress = value
        case .passage(let passage):
            if session.append(passage) {
                wordCount += passage.text.split(whereSeparator: \.isWhitespace).count
                scheduleSave()
            }
        }
    }

    func cancel() {
        guard busy, !cancelling else { return }
        cancelling = true; phase = "Cancelling safely"; job?.cancel()
    }

    func edit(_ id: UUID, text: String) {
        guard !editorLocked else { return }
        session.edit(id, text: text); scheduleSave(); updateSuggestions()
        wordCount = session.passages.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
    }
    func assign(_ id: UUID, speaker: UUID?) { guard !editorLocked else { return }; session.assign(id, speakerID: speaker); scheduleSave() }
    func addSpeaker() { guard !editorLocked else { return }; session.addSpeaker(); scheduleSave() }
    func rename(_ id: UUID, name: String) { guard !editorLocked else { return }; session.rename(id, name: name); scheduleSave() }
    func timestamps(_ value: Bool) { session.includeTimestamps = value; session.changed(); scheduleSave() }
    func split(_ id: UUID, before index: Int) {
        guard !editorLocked else { return }
        do { try session.split(id, beforeWord: index); splitPassage = nil; scheduleSave(); updateSuggestions() }
        catch { notify(error.localizedDescription, error: true) }
    }
    func seek(_ seconds: Double) {
        guard hasVideo else { return }
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    func apply(_ suggestion: NameSuggestion, to speaker: UUID?) {
        guard !editorLocked else { return }
        let target = speaker ?? session.addSpeaker()
        session.rename(target, name: suggestion.name)
        session.assign(suggestion.passageID, speakerID: target)
        scheduleSave()
    }

    func copyAll() {
        guard canExport else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(session.exportText(), forType: .string)
        notify("Transcript copied.")
    }
    func saveText() {
        guard canExport else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = TextPolicy.exportFilename(session.sourceName)
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            try session.exportText().write(to: url, atomically: true, encoding: .utf8)
            session.exportedRevision = session.revision; scheduleSave()
            notify("Transcript saved.")
        } catch { notify("Could not save the transcript. " + error.localizedDescription, error: true) }
    }

    private func scheduleSave() {
        guard !isPreview, !recoveryRequired else { return }
        // Coalesce instead of resetting the deadline: fast speech results must not starve autosave.
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.saveTask = nil
            await self.saveNow()
        }
    }
    func saveNow() async {
        guard !isPreview, !recoveryRequired, !session.sourceName.isEmpty else { return }
        let snapshot = session
        do { try await store.save(snapshot); saveError = nil }
        catch { saveError = TextPolicy.clean("Autosave failed. " + error.localizedDescription) }
    }
    func retrySave() { Task { await saveNow() } }

    private func updateSuggestions() {
        suggestionTask?.cancel()
        let passages = session.passages
        suggestionTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            let result = await Task.detached(priority: .utility) { NameSuggestions.find(in: passages) }.value
            guard !Task.isCancelled else { return }
            self?.suggestions = result
        }
    }

    private func restore() async {
        defer { loading = false }
        do {
            if let saved = try await store.load() {
                session = saved
                wordCount = session.passages.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
                phase = saved.state == .complete ? "Transcript restored" : "Session restored"
                updateSuggestions()
                guard let bookmark = saved.bookmark else { return }
                do {
                    var stale = false
                    let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
                    guard url.startAccessingSecurityScopedResource() else { throw TranscriberError.message("Video access expired.") }
                    accessURL = url
                    let info = try await MediaInfo.inspect(url)
                    let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                    guard abs(info.duration - saved.duration) < 0.25,
                          values.fileSize.map(Int64.init) == saved.sourceSize,
                          values.contentModificationDate == saved.sourceModified else { throw TranscriberError.message("The source video changed.") }
                    tracks = info.tracks; sourceURL = url
                    player.replaceCurrentItem(with: try await makePlayback(url: url, trackID: session.trackID))
                    if stale { session.bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) }
                } catch {
                    releaseVideo()
                    notify("Your transcript is safe. Locate the original video to restore playback.")
                }
                await saveNow()
            }
        } catch {
            recoveryRequired = true
            notify("Could not restore the session. The original file is protected. Preserve it to start a new session.", error: true)
        }
    }

    func preserveSession() {
        Task {
            do { try await store.preserveAndReset(); recoveryRequired = false; notice = nil }
            catch { notify(error.localizedDescription, error: true) }
        }
    }
    private func confirmReplacement() -> Bool {
        guard session.hasUnexportedWork else { return true }
        let alert = NSAlert()
        alert.messageText = "Replace unexported work?"
        alert.informativeText = "This app keeps one current session. Save a text copy before opening another video if you want to keep this transcript."
        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Replace")
        return alert.runModal() == .alertSecondButtonReturn
    }
    private func releaseVideo() {
        player.pause(); player.replaceCurrentItem(with: nil)
        accessURL?.stopAccessingSecurityScopedResource(); accessURL = nil; sourceURL = nil
    }
    func shutdown() async -> Bool {
        cancel()
        await job?.value
        saveTask?.cancel()
        saveTask = nil
        await saveNow()
        if saveError != nil { return false }
        if let timeObserver { player.removeTimeObserver(timeObserver); self.timeObserver = nil }
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver); self.sleepObserver = nil }
        releaseVideo()
        return true
    }

    private func makePreview() {
        session = TranscriptSession(sourceName: "A conversation about good work.mp4", duration: 342, trackID: 1)
        let speaker = session.addSpeaker(); session.rename(speaker, name: "Alex")
        let second = session.addSpeaker()
        session.append(Passage(start: 0, end: 7, text: "Hello, my name is Alex. Today I want to talk about what makes a project worth doing.", speakerID: speaker))
        session.append(Passage(start: 8, end: 15, text: "For me, it starts with a clear purpose. Who are we helping, and what will be better when we are done?", speakerID: second))
        session.append(Passage(start: 16, end: 23, text: "Exactly. The tools matter, but the care we put into the details is what people remember.", speakerID: speaker))
        session.append(Passage(start: 24, end: 31, text: "Then we should make time to listen, test our assumptions, and keep improving the work.", speakerID: second))
        session.state = .complete; session.exportedRevision = session.revision
        phase = "Transcription complete"; progress = 1
        wordCount = session.passages.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
        suggestions = NameSuggestions.find(in: session.passages)
    }
}
