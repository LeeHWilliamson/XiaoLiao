import Foundation
import SwiftData
import XCTest
@testable import XiaoLiao

final class ConversationPersistenceTests: XCTestCase {
    @MainActor
    func testFirstLaunchHasNoPlaceholderHistoryAndUnsentDraftsStayTransient() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = ConversationViewModel.persistent(directory: directory)
        XCTAssertNil(first.storageIssue)
        XCTAssertTrue(first.history.isEmpty)
        first.prompt = "An unsent topic"
        first.draft = "An unsent message"
        first.settings.tone = .warm
        let relaunched = ConversationViewModel.persistent(directory: directory)
        XCTAssertTrue(relaunched.history.isEmpty)
        XCTAssertTrue(relaunched.prompt.isEmpty)
        XCTAssertTrue(relaunched.draft.isEmpty)
        XCTAssertNil(relaunched.activeSessionID)
        XCTAssertEqual(relaunched.settings, ConversationSettings())
    }

    @MainActor
    func testRelaunchRestoresCommittedMessagesSettingsAndSendMethods() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = ConversationViewModel.persistent(directory: directory)
        first.suggestPrompt()
        first.settings.tone = .warm
        XCTAssertTrue(first.startConversation())
        let id = try XCTUnwrap(first.activeSessionID)
        let spoken = first.messages[1]
        first.selectMessage(spoken.id)
        first.perform(.edit, on: spoken.id)
        first.draft = "I love sea turtles."
        XCTAssertTrue(first.submitDraft())
        first.settings.vocabulary = .complex
        first.settings.replyLength = .brief
        first.draft = "A typed reply."
        XCTAssertTrue(first.submitDraft())
        let saved = first.history
        first.draft = "Do not persist this"
        first.selectMessage(first.messages[0].id)
        first.perform(.transcribe, on: first.messages[0].id)

        let relaunched = ConversationViewModel.persistent(directory: directory)
        XCTAssertNil(relaunched.storageIssue)
        XCTAssertEqual(relaunched.history, saved)
        XCTAssertTrue(relaunched.openConversation(id))
        XCTAssertEqual(relaunched.messages[1].content, .text("I love sea turtles."))
        XCTAssertEqual(relaunched.messages[1].communicationMethod, .voice)
        XCTAssertNil(relaunched.messages[1].mockTranslation)
        XCTAssertEqual(relaunched.messages.last?.communicationMethod, .text)
        XCTAssertEqual(relaunched.settings.tone, .warm)
        XCTAssertEqual(relaunched.settings.vocabulary, .complex)
        XCTAssertEqual(relaunched.settings.replyLength, .brief)
        XCTAssertTrue(relaunched.draft.isEmpty)
        XCTAssertTrue(relaunched.details.isEmpty)
        XCTAssertNil(relaunched.selectedMessageID)
        XCTAssertFalse(relaunched.actions(for: relaunched.messages[1]).contains(.edit))
        XCTAssertTrue(relaunched.actions(for: try XCTUnwrap(relaunched.messages.last)).contains(.edit))
    }

    @MainActor
    func testHundredsOfConversationsKeepOrderAndSettingsIndependent() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ConversationHistoryStore(directory: directory)
        XCTAssertTrue(try store.load().isEmpty)
        for index in 0..<300 {
            _ = try store.save(session(id: "session-\(index)", title: "对话 \(index)"))
        }
        var oldest = session(id: "session-0", title: "对话 0")
        oldest.settings.tone = .formal
        _ = try store.save(oldest)
        let reloaded = try ConversationHistoryStore(directory: directory).load()
        XCTAssertEqual(reloaded.count, 300)
        XCTAssertEqual(reloaded.map(\.id), (0..<300).reversed().map { "session-\($0)" })
        XCTAssertEqual(reloaded.last?.settings.tone, .formal)
        XCTAssertEqual(reloaded.first?.settings.tone, .casual)
    }

    @MainActor
    func testCommittedAudioSurvivesTemporaryCleanupAndSandboxRelocation() throws {
        let base = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let directory = base.appendingPathComponent("original", isDirectory: true)
        let moved = base.appendingPathComponent("relocated", isDirectory: true)
        let draft = try makeClip(in: base)
        let bytes = try Data(contentsOf: draft.url)
        var first: ConversationViewModel? = .persistent(directory: directory)
        first?.suggestPrompt()
        XCTAssertTrue(first?.startConversation() == true)
        let id = try XCTUnwrap(first?.activeSessionID)
        XCTAssertTrue(first?.commitRecording(draft, in: id) == true)
        let saved = try XCTUnwrap(first?.messages.last?.localAudio)
        XCTAssertNotEqual(saved.url, draft.url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: draft.url.path))
        XCTAssertEqual(try Data(contentsOf: saved.url), bytes)
        first = nil
        try FileManager.default.moveItem(at: directory, to: moved)

        let relaunched = ConversationViewModel.persistent(directory: moved)
        XCTAssertNil(relaunched.storageIssue)
        XCTAssertTrue(relaunched.openConversation(id))
        let clip = try XCTUnwrap(relaunched.messages.last?.localAudio)
        XCTAssertEqual(clip.url.deletingLastPathComponent(), moved.appendingPathComponent("Recordings", isDirectory: true))
        XCTAssertEqual(try Data(contentsOf: clip.url), bytes)
        XCTAssertEqual(clip.duration, draft.duration)
        XCTAssertTrue(relaunched.isAvailable(.play, for: try XCTUnwrap(relaunched.messages.last)))
        XCTAssertEqual(relaunched.messages.last?.communicationMethod, .voice)
    }

    @MainActor
    func testFailedSavesPreserveOriginalMessagesSettingsAndUnsentText() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let writer = try ConversationHistoryStore(directory: directory)
            _ = try writer.load()
            _ = try writer.save(session(id: "saved", title: "Saved"))
        }
        let reader = try ConversationHistoryStore(directory: directory, allowsSave: false)
        let model = ConversationViewModel.persistent(store: reader)
        XCTAssertTrue(model.openConversation("saved"))
        let original = model.history
        model.settings.tone = .formal
        XCTAssertEqual(model.settings.tone, .casual)
        XCTAssertNotNil(model.storageIssue)
        model.selectMessage(model.messages[1].id)
        model.perform(.edit, on: model.messages[1].id)
        model.draft = "Do not lose this edit"
        XCTAssertFalse(model.submitDraft())
        XCTAssertEqual(model.draft, "Do not lose this edit")
        XCTAssertNotNil(model.editingMessageID)
        XCTAssertEqual(model.history, original)
        XCTAssertEqual(model.messages, original[0].messages)
        XCTAssertEqual(try ConversationHistoryStore(directory: directory).load(), original)
    }

    @MainActor
    func testFailedAudioReplacementKeepsOriginalAndReplacementFiles() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let draft = try makeClip(in: directory)
        var writer: ConversationViewModel? = .persistent(directory: directory.appendingPathComponent("store"))
        writer?.suggestPrompt()
        XCTAssertTrue(writer?.startConversation() == true)
        let id = try XCTUnwrap(writer?.activeSessionID)
        XCTAssertTrue(writer?.commitRecording(draft, in: id) == true)
        let original = try XCTUnwrap(writer?.history.first)
        writer = nil
        let store = try ConversationHistoryStore(directory: directory.appendingPathComponent("store"), allowsSave: false)
        let model = ConversationViewModel.persistent(store: store)
        XCTAssertTrue(model.openConversation(id))
        let message = try XCTUnwrap(model.messages.last)
        model.selectMessage(message.id)
        // Begin editing without granting or accessing an actual microphone.
        model.perform(.edit, on: message.id)
        model.audio.cancelDraft()
        let replacement = try makeClip(in: directory)
        XCTAssertFalse(model.commitRecording(replacement, in: id, replacing: message.id))
        XCTAssertEqual(model.history.first, original)
        XCTAssertEqual(model.messages.last, message)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(message.localAudio).url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: replacement.url.path))
    }

    @MainActor
    func testMissingRecordingDoesNotEraseHistoryOrPretendPlaybackWorks() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = ConversationViewModel.persistent(directory: directory)
        model.suggestPrompt()
        XCTAssertTrue(model.startConversation())
        let id = try XCTUnwrap(model.activeSessionID)
        XCTAssertTrue(model.commitRecording(try makeClip(in: directory), in: id))
        let message = try XCTUnwrap(model.messages.last)
        try FileManager.default.removeItem(at: try XCTUnwrap(message.localAudio).url)
        let relaunched = ConversationViewModel.persistent(directory: directory)
        XCTAssertNotNil(relaunched.storageIssue)
        XCTAssertTrue(relaunched.openConversation(id))
        XCTAssertEqual(relaunched.messages.last, message)
        XCTAssertFalse(relaunched.isAvailable(.play, for: message))
    }

    @MainActor
    func testUnknownPayloadVersionBlocksWritesAndPreservesRecoveryFiles() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let store = try ConversationHistoryStore(directory: directory)
            _ = try store.load()
            _ = try store.save(session(id: "saved", title: "Saved"))
        }
        try changeStoredPayload(in: directory, toVersion: 999)
        let orphan = directory.appendingPathComponent("Recordings/" + UUID().uuidString + ".caf")
        try Data("preserve-for-recovery".utf8).write(to: orphan)
        let relaunched = ConversationViewModel.persistent(directory: directory)
        XCTAssertTrue(relaunched.storageIssue?.canRetryLoading == true)
        relaunched.suggestPrompt()
        XCTAssertFalse(relaunched.startConversation())
        XCTAssertTrue(relaunched.history.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertThrowsError(try ConversationHistoryStore(directory: directory).load())
    }

    @MainActor
    func testClipReferencesRejectPathsOutsideTheRecordingDirectory() throws {
        let decoder = JSONDecoder()
        decoder.userInfo[LocalAudioClip.directoryKey] = URL(fileURLWithPath: "/safe/Recordings", isDirectory: true)
        let malicious = Data("{\"filename\":\"../outside.caf\",\"duration\":1}".utf8)
        XCTAssertThrowsError(try decoder.decode(LocalAudioClip.self, from: malicious))
    }

    @MainActor
    func testInitializationFailureKeepsPromptAndCanRetryWithoutResettingData() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let blocked = directory.appendingPathComponent("occupied")
        let marker = Data("existing-file".utf8)
        try marker.write(to: blocked)
        let model = ConversationViewModel.persistent(directory: blocked)
        XCTAssertTrue(model.storageIssue?.canRetryLoading == true)
        model.prompt = "Keep my topic"
        XCTAssertFalse(model.startConversation())
        XCTAssertEqual(model.prompt, "Keep my topic")
        XCTAssertEqual(try Data(contentsOf: blocked), marker)
        // Remove only the test-created obstruction, then exercise the normal retry.
        try FileManager.default.removeItem(at: blocked)
        model.retryLoadingHistory()
        XCTAssertNil(model.storageIssue)
        XCTAssertTrue(model.startConversation())
        XCTAssertEqual(model.history.count, 1)
    }

    @MainActor
    func testSuccessfulAudioReplacementPersistsAndOnlyThenReclaimsOldClip() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = ConversationViewModel.persistent(directory: directory)
        model.suggestPrompt()
        XCTAssertTrue(model.startConversation())
        let id = try XCTUnwrap(model.activeSessionID)
        XCTAssertTrue(model.commitRecording(try makeClip(in: directory), in: id))
        let original = try XCTUnwrap(model.messages.last)
        model.selectMessage(original.id)
        model.perform(.edit, on: original.id)
        model.audio.cancelDraft()
        XCTAssertTrue(model.commitRecording(try makeClip(in: directory), in: id, replacing: original.id))
        let replacement = try XCTUnwrap(model.messages.last)
        XCTAssertEqual(replacement.id, original.id)
        XCTAssertNotEqual(replacement.localAudio?.url, original.localAudio?.url)
        // Cleanup waits for a successful complete read of all saved references.
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(original.localAudio).url.path))
        let relaunched = ConversationViewModel.persistent(directory: directory)
        XCTAssertTrue(relaunched.openConversation(id))
        XCTAssertEqual(relaunched.messages.last, replacement)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(original.localAudio).url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(replacement.localAudio).url.path))
    }

    @MainActor
    private func session(id: String, title: String) -> ConversationSession {
        ConversationSession(id: id, title: title, prompt: MockConversation.prompt, messages: MockConversation.messages, settings: .init())
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("XiaoLiaoPersistenceTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeClip(in directory: URL) throws -> LocalAudioClip {
        let url = directory.appendingPathComponent(UUID().uuidString + ".caf")
        // Byte preservation is under test here; these fixtures are never played.
        try Data("local-recording-fixture".utf8).write(to: url)
        return LocalAudioClip(url: url, duration: 2.5)
    }

    @MainActor
    private func changeStoredPayload(in directory: URL, toVersion version: Int) throws {
        let schema = Schema([StoredConversation.self])
        let config = ModelConfiguration("ConversationHistory", schema: schema, url: directory.appendingPathComponent("History.store"), cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let record = try XCTUnwrap(context.fetch(FetchDescriptor<StoredConversation>()).first)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: record.payload) as? [String: Any])
        json["version"] = version
        record.payload = try JSONSerialization.data(withJSONObject: json)
        try context.save()
    }
}
