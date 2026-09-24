import Foundation

public enum TextPolicy {
    public static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: String(UnicodeScalar(0x2014)!), with: " - ")
    }

    public static func timestamp(_ seconds: Double) -> String {
        let value = seconds.isFinite ? Int(max(0, min(seconds, 359_999))) : 0
        return String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
    }

    public static func exportFilename(_ source: String) -> String {
        let base = (source as NSString).deletingPathExtension
        let safe = clean(base).replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .components(separatedBy: .controlCharacters).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(safe.isEmpty ? "Video" : String(safe.prefix(150))) transcription.txt"
    }
}

public enum TranscriberError: LocalizedError, Sendable {
    case message(String)
    public var errorDescription: String? {
        switch self { case .message(let value): TextPolicy.clean(value) }
    }
}

public struct TimedWord: Codable, Sendable, Equatable {
    public var text: String
    public var start: Double
    public var end: Double
    public init(text: String, start: Double, end: Double) {
        self.text = TextPolicy.clean(text); self.start = start; self.end = end
    }
}

public struct Passage: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var start: Double
    public var end: Double
    public var originalText: String
    public var text: String
    public var words: [TimedWord]
    public var speakerID: UUID?
    public init(id: UUID = UUID(), start: Double, end: Double, text: String, words: [TimedWord] = [], speakerID: UUID? = nil) {
        self.id = id; self.start = start; self.end = end
        self.originalText = TextPolicy.clean(text).trimmingCharacters(in: .whitespacesAndNewlines)
        self.text = originalText; self.words = words; self.speakerID = speakerID
    }
    public var canSplit: Bool {
        words.count > 1 && text == originalText &&
        words.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines) == originalText
    }
}

public struct Speaker: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public init(id: UUID = UUID(), name: String) { self.id = id; self.name = TextPolicy.clean(name) }
}

public enum TranscriptState: String, Codable, Sendable {
    case ready, transcribing, complete, interrupted, failed
}

public struct TranscriptSession: Codable, Sendable, Equatable {
    public var version = 1
    public var id = UUID()
    public var sourceName: String
    public var duration: Double
    public var trackID: Int32
    public var bookmark: Data?
    public var sourceSize: Int64?
    public var sourceModified: Date?
    public var passages: [Passage] = []
    public var speakers: [Speaker] = []
    public var state: TranscriptState = .ready
    public var includeTimestamps = false
    public var revision: UInt64 = 0
    public var exportedRevision: UInt64?

    public init(sourceName: String = "", duration: Double = 0, trackID: Int32 = 0) {
        self.sourceName = TextPolicy.clean(sourceName); self.duration = duration; self.trackID = trackID
    }
    public var hasUnexportedWork: Bool { !passages.isEmpty && exportedRevision != revision }
    public var isPartial: Bool { state != .complete && !passages.isEmpty }
    public mutating func changed() { revision &+= 1 }

    @discardableResult
    public mutating func append(_ passage: Passage) -> Bool {
        guard passage.start.isFinite, passage.end.isFinite, passage.start >= 0,
              passage.end > passage.start, !passage.text.isEmpty else { return false }
        // Final speech results are chronological. An exact replay must not duplicate text.
        if let last = passages.last, passage.start < last.end - 0.02 { return false }
        passages.append(passage); changed(); return true
    }

    public mutating func edit(_ id: UUID, text: String) {
        guard let index = passages.firstIndex(where: { $0.id == id }) else { return }
        let clean = TextPolicy.clean(text)
        guard passages[index].text != clean else { return }
        passages[index].text = clean; changed()
    }

    public mutating func assign(_ passageID: UUID, speakerID: UUID?) {
        guard speakerID == nil || speakers.contains(where: { $0.id == speakerID }),
              let index = passages.firstIndex(where: { $0.id == passageID }) else { return }
        guard passages[index].speakerID != speakerID else { return }
        passages[index].speakerID = speakerID; changed()
    }

    @discardableResult
    public mutating func addSpeaker() -> UUID {
        let speaker = Speaker(name: "Person \(speakers.count + 1)")
        speakers.append(speaker); changed(); return speaker.id
    }

    public mutating func rename(_ id: UUID, name: String) {
        guard let index = speakers.firstIndex(where: { $0.id == id }) else { return }
        let clean = TextPolicy.clean(name).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean != speakers[index].name else { return }
        speakers[index].name = clean; changed()
    }

    public mutating func split(_ id: UUID, beforeWord index: Int) throws {
        guard let location = passages.firstIndex(where: { $0.id == id }) else { return }
        let passage = passages[location]
        guard passage.canSplit, index > 0, index < passage.words.count else {
            throw TranscriberError.message("Split an unedited passage at a recognized word boundary. Restore its original text first if needed.")
        }
        let cut = passage.words[index].start
        guard cut > passage.start, cut < passage.end else {
            throw TranscriberError.message("This word does not have a usable split time.")
        }
        let leftWords = Array(passage.words[..<index]), rightWords = Array(passage.words[index...])
        let left = Passage(id: passage.id, start: passage.start, end: cut,
                           text: leftWords.map(\.text).joined(), words: leftWords, speakerID: passage.speakerID)
        let right = Passage(start: cut, end: passage.end, text: rightWords.map(\.text).joined(),
                            words: rightWords, speakerID: passage.speakerID)
        passages.replaceSubrange(location...location, with: [left, right]); changed()
    }

    public func exportText() -> String {
        var lines: [String] = []
        if isPartial { lines.append("[Incomplete transcript]") }
        for passage in passages where !passage.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var prefix: [String] = []
            if includeTimestamps { prefix.append("[\(TextPolicy.timestamp(passage.start))]") }
            if let speaker = speakers.first(where: { $0.id == passage.speakerID }) { prefix.append("\(speaker.name):") }
            lines.append((prefix.isEmpty ? "" : prefix.joined(separator: " ") + " ") + passage.text)
        }
        return TextPolicy.clean(lines.joined(separator: "\n\n")) + (lines.isEmpty ? "" : "\n")
    }
}

/// Generation ownership is separate from the stored session so late callbacks cannot edit a new job.
public struct JobGate: Sendable {
    public private(set) var current: UUID?
    public init() {}
    public mutating func begin() -> UUID { let id = UUID(); current = id; return id }
    public mutating func invalidate() { current = nil }
    public func accepts(_ id: UUID) -> Bool { current == id }
}
