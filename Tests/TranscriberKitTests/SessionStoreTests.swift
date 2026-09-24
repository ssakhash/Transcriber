import Foundation
import Testing
@testable import TranscriberKit

struct SessionStoreTests {
    func temporary() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func roundTripAndInterruptedRecovery() async throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(url: directory.appendingPathComponent("session.json"))
        var session = TranscriptSession(sourceName: "example.mp4", duration: 600, trackID: 2)
        session.state = .transcribing
        session.append(Passage(start: 2, end: 5, text: "Kept after a crash."))
        try await store.save(session)
        let restored = try #require(await store.load())
        #expect(restored.passages == session.passages)
        #expect(restored.state == .interrupted)
        #expect(restored.revision > session.revision)
    }

    @Test(arguments: ["{broken", "{\"version\":99}"])
    func unreadableSessionsCannotBeOverwritten(_ content: String) async throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("session.json")
        try content.write(to: url, atomically: true, encoding: .utf8)
        let store = SessionStore(url: url)
        await #expect(throws: (any Error).self) { try await store.load() }
        await #expect(throws: (any Error).self) { try await store.save(TranscriptSession()) }
        #expect(try String(contentsOf: url, encoding: .utf8) == content)
        try await store.preserveAndReset()
        try await store.save(TranscriptSession(sourceName: "new.mp4"))
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let backup = try #require(files.first { $0.lastPathComponent.hasPrefix("session-preserved-") })
        #expect(try String(contentsOf: backup, encoding: .utf8) == content)
    }

    @Test func invalidSessionIsProtected() async throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("session.json")
        var session = TranscriptSession(); let passage = Passage(start: 1, end: 3, text: "Original")
        session.passages = [passage, passage]
        try JSONEncoder().encode(session).write(to: url)
        let store = SessionStore(url: url)
        await #expect(throws: (any Error).self) { try await store.load() }
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func failedSaveDoesNotReplacePreviousFile() async throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("session.json")
        let store = SessionStore(url: url)
        try await store.save(TranscriptSession(sourceName: "original.mp4"))
        let original = try Data(contentsOf: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        do {
            try await store.save(TranscriptSession(sourceName: "replacement.mp4"))
            Issue.record("A read-only destination unexpectedly accepted a save")
        } catch { #expect(try Data(contentsOf: url) == original) }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }
}
