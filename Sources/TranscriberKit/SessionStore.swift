import Foundation

public actor SessionStore {
    public let url: URL
    private var blocked = false
    public init(url: URL) { self.url = url }

    public func load() throws -> TranscriptSession? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let header = try JSONDecoder().decode(Header.self, from: data)
            guard header.version == 1 else { throw TranscriberError.message("This session uses a newer format. The saved file has been preserved.") }
            var session = try JSONDecoder().decode(TranscriptSession.self, from: data)
            guard session.duration.isFinite, session.duration >= 0,
                  Set(session.passages.map(\.id)).count == session.passages.count,
                  Set(session.speakers.map(\.id)).count == session.speakers.count else {
                throw TranscriberError.message("The saved session is invalid. Its original file has been preserved.")
            }
            var previousEnd: Double = 0
            for passage in session.passages {
                guard passage.start.isFinite, passage.end.isFinite, passage.start >= previousEnd - 0.02,
                      passage.end > passage.start,
                      passage.words.allSatisfy({ $0.start.isFinite && $0.end.isFinite && $0.end >= $0.start }),
                      passage.speakerID == nil || session.speakers.contains(where: { $0.id == passage.speakerID }) else {
                    throw TranscriberError.message("The saved transcript is invalid. Its original file has been preserved.")
                }
                previousEnd = passage.end
            }
            session.sourceName = TextPolicy.clean(session.sourceName)
            for index in session.passages.indices {
                session.passages[index].text = TextPolicy.clean(session.passages[index].text)
                session.passages[index].originalText = TextPolicy.clean(session.passages[index].originalText)
                for word in session.passages[index].words.indices {
                    session.passages[index].words[word].text = TextPolicy.clean(session.passages[index].words[word].text)
                }
            }
            for index in session.speakers.indices { session.speakers[index].name = TextPolicy.clean(session.speakers[index].name) }
            if session.state == .transcribing { session.state = .interrupted; session.changed() }
            return session
        } catch { blocked = true; throw error }
    }

    public func save(_ session: TranscriptSession) throws {
        guard !blocked else { throw TranscriberError.message("Saving is paused to protect an unreadable session. Preserve it before starting a new session.") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(session)
        try data.write(to: url, options: .atomic)
    }

    public func preserveAndReset() throws {
        if FileManager.default.fileExists(atPath: url.path) {
            let backup = url.deletingLastPathComponent().appendingPathComponent("session-preserved-\(UUID().uuidString).json")
            try FileManager.default.moveItem(at: url, to: backup)
        }
        blocked = false
    }
    private struct Header: Decodable { let version: Int }
}
