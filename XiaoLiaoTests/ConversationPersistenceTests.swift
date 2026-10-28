import Foundation
import SwiftData
import XCTest
@testable import XiaoLiao

final class ConversationPersistenceTests: XCTestCase {
    @MainActor
    func testFreshHistoryAndUnsentDraftsStayTransient() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = ConversationViewModel.persistent(directory: directory)
        XCTAssertNil(model.storageIssue)
        XCTAssertTrue(model.history.isEmpty)
        model.prompt = "Unsent"
        model.draft = "Unsent text"
        model.settings.tone = .warm
        let relaunched = ConversationViewModel.persistent(directory: directory)
        XCTAssertTrue(relaunched.history.isEmpty)
        XCTAssertTrue(relaunched.prompt.isEmpty)
        XCTAssertTrue(relaunched.draft.isEmpty)
        XCTAssertEqual(relaunched.settings, ConversationSettings())
    }

    @MainActor
    func testRelaunchRetainsAllVersionsAndDisplaysOnlyLatest() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = makeConversation(directory: directory)
        let id = try XCTUnwrap(model.activeSessionID)
        let original = model.messages[1]
        model.selectMessage(original.id)
        model.perform(.edit, on: original.id)
        model.draft = "I love sea turtles."
        XCTAssertTrue(model.submitDraft())
        let edited = model.messages[1]
        model.settings.tone = .formal
        model.settings.vocabulary = .complex
        model.settings.replyLength = .brief
        model.draft = "A typed reply"
        XCTAssertTrue(model.submitDraft())
        let saved = model.history
        model.draft = "Unsent edit"
        let relaunched = ConversationViewModel.persistent(directory: directory)
        XCTAssertEqual(relaunched.history, saved)
        XCTAssertTrue(relaunched.openConversation(id))
        XCTAssertEqual(relaunched.messageVersions.count, 4)
        XCTAssertEqual(relaunched.messages.count, 3)
        XCTAssertEqual(relaunched.messageVersions[1], original)
        XCTAssertEqual(relaunched.messages[1], edited)
        XCTAssertEqual(edited.replacesMessageID, original.id)
        XCTAssertEqual(edited.modality, .spoken)
        XCTAssertEqual(relaunched.messages.last?.modality, .written)
        XCTAssertEqual(relaunched.settings.tone, .formal)
        XCTAssertEqual(relaunched.settings.replyLength, .brief)
        XCTAssertTrue(relaunched.draft.isEmpty)
        XCTAssertNil(relaunched.selectedMessageID)
        XCTAssertFalse(relaunched.isAvailable(.edit, for: edited))
    }

    @MainActor
    func testHundredsOfConversationsKeepOrderAndIndependentSettings() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ConversationHistoryStore(directory: directory)
        _ = try store.load()
        for index in 0..<300 { _ = try store.save(session(id: "session-\(index)")) }
        var oldest = session(id: "session-0")
        oldest.settings.tone = .formal
        _ = try store.save(oldest)
        let loaded = try ConversationHistoryStore(directory: directory).load()
        XCTAssertEqual(loaded.map(\.id), (0..<300).reversed().map { "session-\($0)" })
        XCTAssertEqual(loaded.last?.settings.tone, .formal)
        XCTAssertEqual(loaded.first?.settings.tone, .casual)
    }

    @MainActor
    func testAudioCopiesUseRelativeKeysAndSurviveRelocation() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let originalStore = directory.appendingPathComponent("original")
        let relocatedStore = directory.appendingPathComponent("relocated")
        let draft = try makeClip(in: directory)
        let bytes = try Data(contentsOf: draft.url)
        var model: ConversationViewModel? = makeConversation(directory: originalStore)
        let id = try XCTUnwrap(model?.activeSessionID)
        XCTAssertTrue(model?.commitRecording(draft, in: id) == true)
        let sent = try XCTUnwrap(model?.messages.last)
        let key = try XCTUnwrap(sent.audioAttachment?.storageKey)
        XCTAssertFalse(key.contains("/"))
        XCTAssertNotEqual(key, draft.url.lastPathComponent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: draft.url.path))
        model = nil
        try FileManager.default.moveItem(at: originalStore, to: relocatedStore)
        let relaunched = ConversationViewModel.persistent(directory: relocatedStore)
        XCTAssertTrue(relaunched.openConversation(id))
        let loaded = try XCTUnwrap(relaunched.messages.last)
        XCTAssertEqual(loaded, sent)
        let clip = try XCTUnwrap(relaunched.audioClip(for: loaded))
        XCTAssertEqual(clip.url.deletingLastPathComponent(), relocatedStore.appendingPathComponent("Recordings", isDirectory: true))
        XCTAssertEqual(try Data(contentsOf: clip.url), bytes)
        XCTAssertTrue(relaunched.isAvailable(.play, for: loaded))
    }

    @MainActor
    func testAudioReplacementRetainsOriginalVersionAndBothRecordingsAfterRelaunch() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = makeConversation(directory: directory)
        let id = try XCTUnwrap(model.activeSessionID)
        XCTAssertTrue(model.commitRecording(try makeClip(in: directory), in: id))
        let original = try XCTUnwrap(model.messages.last)
        let originalURL = try XCTUnwrap(model.audioClip(for: original)).url
        model.selectMessage(original.id)
        model.perform(.edit, on: original.id)
        model.audio.cancelDraft()
        XCTAssertTrue(model.commitRecording(try makeClip(in: directory), in: id, replacing: original.id))
        let replacement = try XCTUnwrap(model.messages.last)
        XCTAssertNotEqual(replacement.id, original.id)
        XCTAssertEqual(replacement.replacesMessageID, original.id)
        let relaunched = ConversationViewModel.persistent(directory: directory)
        XCTAssertTrue(relaunched.openConversation(id))
        XCTAssertEqual(relaunched.messages.last, replacement)
        XCTAssertEqual(relaunched.messageVersions[2], original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path))
        XCTAssertNotNil(relaunched.audioClip(for: original))
        XCTAssertNotNil(relaunched.audioClip(for: replacement))
    }

    @MainActor
    func testFailedSavesKeepDraftSettingsAndOriginalRecording() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = makeConversation(directory: directory)
        let id = try XCTUnwrap(writer.activeSessionID)
        XCTAssertTrue(writer.commitRecording(try makeClip(in: directory), in: id))
        let saved = writer.history
        let reader = try ConversationHistoryStore(directory: directory, allowsSave: false)
        let model = ConversationViewModel.persistent(store: reader, audio: ConversationAudioController(permissionRequest: { false }))
        XCTAssertTrue(model.openConversation(id))
        model.settings.tone = .formal
        XCTAssertEqual(model.settings.tone, .casual)
        model.draft = "Keep this text"
        XCTAssertFalse(model.submitDraft())
        XCTAssertEqual(model.draft, "Keep this text")
        let original = try XCTUnwrap(model.messages.last)
        model.selectMessage(original.id)
        model.perform(.edit, on: original.id)
        model.audio.cancelDraft()
        let replacement = try makeClip(in: directory)
        XCTAssertFalse(model.commitRecording(replacement, in: id, replacing: original.id))
        XCTAssertEqual(model.history, saved)
        XCTAssertNotNil(model.audioClip(for: original))
        XCTAssertTrue(FileManager.default.fileExists(atPath: replacement.url.path))
    }

    @MainActor
    func testMissingRecordingPreservesMessageMetadataAndDisablesPlay() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = makeConversation(directory: directory)
        let id = try XCTUnwrap(model.activeSessionID)
        XCTAssertTrue(model.commitRecording(try makeClip(in: directory), in: id))
        let message = try XCTUnwrap(model.messages.last)
        try FileManager.default.removeItem(at: try XCTUnwrap(model.audioClip(for: message)).url)
        let relaunched = ConversationViewModel.persistent(directory: directory)
        XCTAssertNotNil(relaunched.storageIssue)
        XCTAssertTrue(relaunched.openConversation(id))
        XCTAssertEqual(relaunched.messages.last, message)
        XCTAssertFalse(relaunched.isAvailable(.play, for: message))
    }

    @MainActor
    func testSystemExchangePersistsExactReplyTargetAndFailureKeepsArmedDraft() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = makeConversation(directory: directory)
        let id = try XCTUnwrap(model.activeSessionID)
        model.toggleSystemMessageMode()
        model.draft = MockConversation.systemRequest
        XCTAssertTrue(model.submitDraft())
        let records = model.messageVersions
        let relaunched = ConversationViewModel.persistent(directory: directory)
        XCTAssertTrue(relaunched.openConversation(id))
        XCTAssertEqual(relaunched.messageVersions, records)
        XCTAssertEqual(relaunched.messages.last?.replyToMessageID, relaunched.messages[2].id)
        XCTAssertEqual(relaunched.settings.vocabulary, .simple)
        XCTAssertFalse(relaunched.isSystemMessageMode)
        let reader = try ConversationHistoryStore(directory: directory, allowsSave: false)
        let readOnly = ConversationViewModel.persistent(store: reader)
        XCTAssertTrue(readOnly.openConversation(id))
        readOnly.toggleSystemMessageMode()
        readOnly.draft = MockConversation.systemSettingsQuestion
        XCTAssertFalse(readOnly.submitDraft())
        XCTAssertTrue(readOnly.isSystemMessageMode)
        XCTAssertEqual(readOnly.draft, MockConversation.systemSettingsQuestion)
        XCTAssertEqual(readOnly.messageVersions, records)
    }

    @MainActor
    func testObservationsPersistAgainstExactVersionsWithoutGeneratingAnalyses() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = makeConversation(directory: directory)
        let id = try XCTUnwrap(model.activeSessionID)
        let original = model.messages[1]
        XCTAssertTrue(model.grammarObservations.isEmpty)
        XCTAssertTrue(model.vocabularyObservations.isEmpty)
        let initialGrammar = grammar(for: original)
        let initialVocabulary = vocabulary(for: original)
        XCTAssertTrue(model.recordGrammarObservation(initialGrammar))
        XCTAssertTrue(model.recordVocabularyObservation(initialVocabulary))
        model.selectMessage(original.id)
        model.perform(.edit, on: original.id)
        model.draft = "Yes, turtles are great."
        XCTAssertTrue(model.submitDraft())
        let edited = model.messages[1]
        XCTAssertEqual(model.grammarObservations, [initialGrammar])
        XCTAssertTrue(model.recordGrammarObservation(self.grammar(for: edited)))
        // Re-evaluation supersedes only the evaluation of that exact version.
        let reEvaluated = self.grammar(for: original)
        XCTAssertTrue(model.recordGrammarObservation(reEvaluated))
        XCTAssertEqual(model.grammarObservations.count, 2)
        XCTAssertFalse(model.grammarObservations.contains(where: { $0.id == initialGrammar.id }))
        let relaunched = ConversationViewModel.persistent(directory: directory)
        XCTAssertTrue(relaunched.openConversation(id))
        XCTAssertEqual(relaunched.grammarObservations, model.grammarObservations)
        XCTAssertEqual(relaunched.vocabularyObservations, [initialVocabulary])
        XCTAssertEqual(relaunched.messages[1].id, edited.id)
        XCTAssertEqual(relaunched.messageVersions[1].id, initialVocabulary.metadata.messageID)
    }

    @MainActor
    func testInvalidObservationsAndFailedObservationSaveDoNotMutateSession() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = makeConversation(directory: directory)
        let id = try XCTUnwrap(model.activeSessionID)
        let message = model.messages[1]
        XCTAssertFalse(model.recordGrammarObservation(grammar(for: message, revision: 99)))
        XCTAssertFalse(model.recordGrammarObservation(grammar(for: model.messages[0])))
        XCTAssertFalse(model.recordGrammarObservation(grammar(for: message, start: Int.max)))
        XCTAssertFalse(model.recordGrammarObservation(grammar(for: message, confidence: 1.1)))
        XCTAssertFalse(model.recordGrammarObservation(grammar(for: message, conversationID: "another")))
        XCTAssertTrue(model.grammarObservations.isEmpty)
        let reader = try ConversationHistoryStore(directory: directory, allowsSave: false)
        let readOnly = ConversationViewModel.persistent(store: reader)
        XCTAssertTrue(readOnly.openConversation(id))
        XCTAssertFalse(readOnly.recordGrammarObservation(grammar(for: message)))
        XCTAssertFalse(readOnly.recordVocabularyObservation(vocabulary(for: message)))
        XCTAssertTrue(readOnly.grammarObservations.isEmpty)
        XCTAssertTrue(readOnly.vocabularyObservations.isEmpty)
        XCTAssertTrue(try ConversationHistoryStore(directory: directory).load()[0].grammarObservations.isEmpty)
    }

    @MainActor
    func testObservationSourcesAndUnicodeSpansReferToTheExactText() throws {
        let model = ConversationViewModel(history: [])
        model.suggestPrompt()
        XCTAssertTrue(model.startConversation())
        model.draft = "I 🐢 love turtles."
        XCTAssertTrue(model.submitDraft())
        let message = try XCTUnwrap(model.messages.last)
        let missingTranscript = GrammarObservation(metadata: metadata(for: message, source: .speechTranscription), opportunities: [])
        XCTAssertFalse(model.recordGrammarObservation(missingTranscript))

        let assessment = VocabularyObservation.Assessment(category: .init(categoryID: "word-choice", subcategoryID: nil),
                                                         outcome: .appropriate, suggestedReplacement: nil, explanation: nil, confidence: nil)
        func observation(start: Int, length: Int, surface: String) -> VocabularyObservation {
            VocabularyObservation(metadata: metadata(for: message), usages: [
                .init(id: UUID().uuidString, unitKind: .word, surfaceText: surface, lemma: nil,
                      textSpan: .init(startUTF16: start, lengthUTF16: length), assessments: [assessment])
            ])
        }
        // UTF-16 offsets count the turtle as two units. Split surrogates and stale
        // surface text must be rejected rather than highlighting a different word.
        XCTAssertFalse(model.recordVocabularyObservation(observation(start: 2, length: 1, surface: "🐢")))
        XCTAssertFalse(model.recordVocabularyObservation(observation(start: 5, length: 4, surface: "like")))
        let valid = observation(start: 5, length: 4, surface: "love")
        XCTAssertTrue(model.recordVocabularyObservation(valid))
        XCTAssertEqual(model.vocabularyObservations, [valid])
        let noApplicableRules = GrammarObservation(metadata: metadata(for: message), opportunities: [])
        XCTAssertTrue(model.recordGrammarObservation(noApplicableRules))
        XCTAssertEqual(model.grammarObservations, [noApplicableRules])
    }

    @MainActor
    func testInvalidEditChainsAndCrossConversationMessagesAreRejected() throws {
        var original = session(id: "one")
        let message = original.messages[1]
        original.messages.append(message.edited(content: .text("First edit")))
        original.messages.append(message.edited(content: .text("Forked edit")))
        XCTAssertThrowsError(try original.validate())
        var other = session(id: "two")
        other.messages.append(message)
        XCTAssertThrowsError(try other.validate())
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ConversationHistoryStore(directory: directory)
        _ = try store.load()
        XCTAssertThrowsError(try store.save(original))
        XCTAssertTrue(try store.load().isEmpty)
        XCTAssertNil(store.recordingURL(for: "../outside.caf"))
    }

    @MainActor
    func testUnknownPayloadVersionPreservesRecoveryFilesAndBlocksWrites() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let store = try ConversationHistoryStore(directory: directory)
            _ = try store.load()
            _ = try store.save(session(id: "saved"))
        }
        try changeStoredVersion(in: directory)
        let orphan = directory.appendingPathComponent("Recordings/" + UUID().uuidString + ".caf")
        try Data("preserve".utf8).write(to: orphan)
        let model = ConversationViewModel.persistent(directory: directory)
        XCTAssertTrue(model.storageIssue?.canRetryLoading == true)
        model.suggestPrompt()
        XCTAssertFalse(model.startConversation())
        XCTAssertTrue(FileManager.default.fileExists(atPath: orphan.path))
    }

    @MainActor
    func testInitializationFailureCanRetryWithoutResettingExistingFile() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let blocked = directory.appendingPathComponent("occupied")
        let marker = Data("existing-file".utf8)
        try marker.write(to: blocked)
        let model = ConversationViewModel.persistent(directory: blocked)
        model.prompt = "Keep my topic"
        XCTAssertFalse(model.startConversation())
        XCTAssertEqual(try Data(contentsOf: blocked), marker)
        XCTAssertEqual(model.prompt, "Keep my topic")
        try FileManager.default.removeItem(at: blocked)
        model.retryLoadingHistory()
        XCTAssertTrue(model.startConversation())
    }

    @MainActor
    private func makeConversation(directory: URL) -> ConversationViewModel {
        let model = ConversationViewModel.persistent(directory: directory, audio: ConversationAudioController(permissionRequest: { false }))
        model.suggestPrompt()
        XCTAssertTrue(model.startConversation())
        return model
    }

    @MainActor
    private func session(id: String) -> ConversationSession {
        ConversationSession(id: id, title: id, prompt: MockConversation.prompt,
                            messages: MockConversation.messages(conversationID: id), settings: .init())
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("XiaoLiaoPersistenceTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeClip(in directory: URL) throws -> LocalAudioClip {
        let url = directory.appendingPathComponent(UUID().uuidString + ".caf")
        // Byte-copy fixtures are never played or passed through a recognizer.
        try Data("local-recording-fixture".utf8).write(to: url)
        return LocalAudioClip(url: url, duration: 2.5)
    }

    private func metadata(for message: Message, revision: Int? = nil, conversationID: String? = nil,
                          source: ObservationMetadata.TextSource = .messageText) -> ObservationMetadata {
        ObservationMetadata(id: UUID().uuidString, messageID: message.id,
                            conversationID: conversationID ?? message.conversationID,
                            messageRevision: revision ?? message.revision, textSource: source,
                            evaluatedAt: Date(), provenance: .init(method: .manual, evaluatorID: "test-fixture",
                            evaluatorVersion: "1", rubricVersion: "1", taxonomyVersion: "1"), confidence: nil)
    }

    private func grammar(for message: Message, revision: Int? = nil, start: Int = 0,
                         confidence: Double? = nil, conversationID: String? = nil) -> GrammarObservation {
        GrammarObservation(metadata: metadata(for: message, revision: revision, conversationID: conversationID),
                           opportunities: [.init(id: UUID().uuidString, category: .init(categoryID: "test-rule", subcategoryID: nil),
                           textSpan: .init(startUTF16: start, lengthUTF16: 1), outcome: .correct,
                           suggestedCorrection: nil, explanation: nil, confidence: confidence)])
    }

    private func vocabulary(for message: Message) -> VocabularyObservation {
        VocabularyObservation(metadata: metadata(for: message), usages: [
            .init(id: UUID().uuidString, unitKind: .word, surfaceText: "Yes", lemma: "yes",
                  textSpan: .init(startUTF16: 0, lengthUTF16: 3), assessments: [
                    .init(category: .init(categoryID: "word-choice", subcategoryID: nil), outcome: .appropriate,
                          suggestedReplacement: nil, explanation: nil, confidence: nil)
                  ])
        ])
    }

    @MainActor
    private func changeStoredVersion(in directory: URL) throws {
        let schema = Schema([StoredConversation.self])
        let config = ModelConfiguration("ConversationHistory", schema: schema, url: directory.appendingPathComponent("History.store"), cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let record = try XCTUnwrap(context.fetch(FetchDescriptor<StoredConversation>()).first)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: record.payload) as? [String: Any])
        json["version"] = 999
        record.payload = try JSONSerialization.data(withJSONObject: json)
        try context.save()
    }
}
