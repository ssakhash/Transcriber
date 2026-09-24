import Foundation
import Testing
@testable import TranscriberKit

struct TranscriptTests {
    func passage() -> Passage {
        Passage(start: 2, end: 6, text: "Hello there, Alex.", words: [
            TimedWord(text: "Hello ", start: 2, end: 3),
            TimedWord(text: "there, ", start: 3, end: 4),
            TimedWord(text: "Alex.", start: 4, end: 6)
        ])
    }

    @Test func normalizationAndFilename() {
        let dash = String(UnicodeScalar(0x2014)!)
        #expect(TextPolicy.clean("one\(dash)two") == "one - two")
        #expect(TextPolicy.exportFilename("Interview.final.mp4") == "Interview.final transcription.txt")
        #expect(TextPolicy.exportFilename("Q\(dash)A.mp4") == "Q - A transcription.txt")
        #expect(TextPolicy.timestamp(3661.5) == "01:01:01")
        #expect(TextPolicy.timestamp(.nan) == "00:00:00")
    }

    @Test func chronologicalAssemblyRejectsReplayAndInvalidTimes() {
        var session = TranscriptSession()
        let first = session.append(passage())
        let replay = session.append(passage())
        let invalidStart = session.append(Passage(start: .nan, end: 8, text: "bad"))
        let invalidEnd = session.append(Passage(start: 7, end: 6, text: "bad"))
        let next = session.append(Passage(start: 7, end: 9, text: "Next."))
        #expect(first && next)
        #expect(!replay && !invalidStart && !invalidEnd)
        #expect(session.passages.count == 2)
    }

    @Test func editsKeepTimingAndNormalize() {
        var session = TranscriptSession()
        let first = passage(); session.append(first)
        session.edit(first.id, text: "Edited" + String(UnicodeScalar(0x2014)!) + "text")
        #expect(session.passages[0].text == "Edited - text")
        #expect(session.passages[0].start == 2 && session.passages[0].end == 6)
        #expect(session.passages[0].originalText == first.text)
        #expect(!session.passages[0].canSplit)
    }

    @Test func splittingPreservesWordsTimingAndSpeaker() throws {
        var session = TranscriptSession()
        let speaker = session.addSpeaker()
        let first = passage(); session.append(first); session.assign(first.id, speakerID: speaker)
        try session.split(first.id, beforeWord: 2)
        #expect(session.passages.count == 2)
        #expect(session.passages[0].text == "Hello there,")
        #expect(session.passages[1].text == "Alex.")
        #expect(session.passages[0].end == 4 && session.passages[1].start == 4)
        #expect(session.passages.allSatisfy { $0.speakerID == speaker })
        #expect(session.passages[0].id == first.id)
        #expect(session.passages[0].id != session.passages[1].id)
    }

    @Test func unsafeSplitsAreRefused() {
        var session = TranscriptSession()
        let first = passage(); session.append(first)
        #expect(throws: (any Error).self) { try session.split(first.id, beforeWord: 0) }
        session.edit(first.id, text: "Corrections")
        #expect(throws: (any Error).self) { try session.split(first.id, beforeWord: 1) }
        var incomplete = passage(); incomplete.words.removeLast()
        #expect(!incomplete.canSplit)
    }

    @Test func speakerRenameAndExportConsistency() {
        var session = TranscriptSession(sourceName: "Interview.mp4")
        let first = passage(); session.append(first)
        let speaker = session.addSpeaker(); session.assign(first.id, speakerID: speaker)
        session.rename(speaker, name: "Alex Morgan")
        session.state = .complete
        #expect(session.exportText() == "Alex Morgan: Hello there, Alex.\n")
        session.includeTimestamps = true
        #expect(session.exportText() == "[00:00:02] Alex Morgan: Hello there, Alex.\n")
        session.rename(speaker, name: "  ")
        #expect(session.speakers[0].name == "Alex Morgan")
        session.assign(first.id, speakerID: UUID())
        #expect(session.passages[0].speakerID == speaker)
    }

    @Test func partialOutputAndDirtyTracking() {
        var session = TranscriptSession(); let first = passage(); session.append(first)
        session.state = .interrupted
        #expect(session.exportText().hasPrefix("[Incomplete transcript]"))
        #expect(session.hasUnexportedWork)
        session.exportedRevision = session.revision
        #expect(!session.hasUnexportedWork)
        session.edit(first.id, text: "Corrected")
        #expect(session.hasUnexportedWork)
    }

    @Test func staleCallbacksCannotEnterNewJob() {
        var gate = JobGate(); let first = gate.begin()
        #expect(gate.accepts(first))
        gate.invalidate(); #expect(!gate.accepts(first))
        let second = gate.begin()
        #expect(!gate.accepts(first)); #expect(gate.accepts(second))
    }

    @Test func namesRequireAnIntroduction() {
        let negative = ["I am happy to be here.", "My name is not important.", "We spoke with John Smith yesterday.", "I'm a software engineer.", "I am not Alex."]
        for text in negative {
            #expect(NameSuggestions.find(in: [Passage(start: 0, end: 4, text: text)]).isEmpty)
        }
        let positive = Passage(start: 8, end: 12, text: "Hello, my name is John Smith. Thank you for joining us.")
        let suggestions = NameSuggestions.find(in: [positive, positive])
        #expect(suggestions.count == 1)
        #expect(suggestions.first?.name == "John Smith")
        #expect(suggestions.first?.time == 8)
        #expect(suggestions.first?.passageID == positive.id)
    }
}
