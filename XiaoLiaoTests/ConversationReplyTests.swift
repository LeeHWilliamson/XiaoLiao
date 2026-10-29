import Foundation
import XCTest
@testable import XiaoLiao

final class ConversationReplyTests: XCTestCase {
    @MainActor
    func testLiveConversationStartsEmptyAndStoresOnlyRealPartnerResults() async throws {
        let probe = ReplyProbe()
        let model = makeModel(probe)
        model.prompt = "Ordering tea"
        model.settings.tone = .warm
        XCTAssertTrue(model.startConversation())
        XCTAssertTrue(model.messages.isEmpty)
        XCTAssertNotNil(model.pendingReply)
        XCTAssertTrue(model.isGeneratingReply)
        XCTAssertEqual(model.inputMode, .text)
        await model.waitForPendingReplies()
        let partner = try XCTUnwrap(model.messages.first)
        XCTAssertEqual(model.messages.count, 1)
        XCTAssertEqual(partner.senderRole, .aiPartner)
        XCTAssertEqual(partner.modality, .written)
        XCTAssertEqual(partner.origin, .interaction)
        XCTAssertNotNil(partner.generation)
        XCTAssertNil(partner.replyToMessageID)
        XCTAssertNil(model.pendingReply)
        let calls = await probe.calls
        XCTAssertEqual(calls.first?.prompt, "Ordering tea")
        XCTAssertEqual(calls.first?.settings.tone, .warm)
        XCTAssertTrue(calls.first?.messages.isEmpty == true)
    }

    @MainActor
    func testTextAndEditsGetExactVersionRepliesAndKeepLocalStatistics() async throws {
        let model = makeModel(ReplyProbe())
        model.suggestPrompt()
        XCTAssertTrue(model.startConversation())
        await model.waitForPendingReplies()
        model.draft = "I like tea."
        XCTAssertTrue(model.submitDraft())
        let original = try XCTUnwrap(model.messages.last)
        await model.waitForPendingReplies()
        XCTAssertEqual(model.messages.last?.replyToMessageID, original.id)
        model.selectMessage(original.id)
        model.perform(.edit, on: original.id)
        XCTAssertEqual(model.editingMessageID, original.id)
        model.draft = "I love green tea."
        XCTAssertTrue(model.submitDraft())
        let edit = try XCTUnwrap(model.messages.first { $0.logicalMessageID == original.logicalMessageID })
        XCTAssertEqual(edit.replacesMessageID, original.id)
        XCTAssertEqual(edit.modality, .written)
        await model.waitForPendingReplies()
        XCTAssertEqual(model.messages.last?.replyToMessageID, edit.id)
        XCTAssertTrue(model.messageVersions.contains(original))
        XCTAssertEqual(model.messageVersions.filter { $0.senderRole == .aiPartner }.count, 3)
        let stats = try await model.statisticsSnapshot()
        XCTAssertEqual(stats.overall.practiceAttempts, 2)
        XCTAssertEqual(stats.overall.sentenceCount, 2)
        XCTAssertNil(model.storageIssue)
    }

    @MainActor
    func testFailedSendKeepsCommittedTextAndRetryReusesTheImmutableRequest() async throws {
        let probe = ReplyProbe(failAt: 2)
        let model = makeModel(probe)
        model.suggestPrompt()
        XCTAssertTrue(model.startConversation())
        await model.waitForPendingReplies()
        model.draft = "A cup of tea, please."
        XCTAssertTrue(model.submitDraft())
        let user = try XCTUnwrap(model.messages.last)
        await model.waitForPendingReplies()
        let job = try XCTUnwrap(model.pendingReply)
        XCTAssertEqual(model.messages.last, user)
        XCTAssertTrue(model.draft.isEmpty)
        XCTAssertNotNil(job.failureMessage)
        XCTAssertFalse(model.isGeneratingReply)
        model.settings.tone = .formal
        model.draft = "Keep this draft"
        XCTAssertFalse(model.submitDraft())
        model.retryReply()
        model.retryReply()
        await model.waitForPendingReplies()
        let calls = await probe.calls
        XCTAssertEqual(calls.count, 3)
        XCTAssertEqual(calls[1], calls[2])
        XCTAssertEqual(model.messages.last?.id, job.request.requestID)
        XCTAssertEqual(model.messages.last?.replyToMessageID, user.id)
        XCTAssertEqual(model.settings.tone, .formal)
        XCTAssertEqual(model.draft, "Keep this draft")
        XCTAssertNil(model.pendingReply)
        model.retryReply()
        await model.waitForPendingReplies()
        let callsAfterCompletion = await probe.calls
        XCTAssertEqual(callsAfterCompletion.count, 3)
    }

    @MainActor
    func testDelayedReplyMergesOnlyIntoItsOwningConversation() async throws {
        let started = expectation(description: "Second request is in flight")
        let probe = ReplyProbe(pauseAt: 2, onPause: { started.fulfill() })
        defer { Task { await probe.release() } }
        let model = makeModel(probe)
        model.prompt = "First conversation"
        XCTAssertTrue(model.startConversation())
        await model.waitForPendingReplies()
        let firstID = try XCTUnwrap(model.activeSessionID)
        model.draft = "I like tea."
        XCTAssertTrue(model.submitDraft())
        let target = try XCTUnwrap(model.messages.last)
        await fulfillment(of: [started], timeout: 2)
        model.settings.tone = .warm
        model.prepareNewConversation()
        model.prompt = "Second conversation"
        XCTAssertTrue(model.startConversation())
        let currentID = model.activeSessionID
        model.settings.vocabulary = .complex
        model.draft = "Do not erase this"
        await probe.release()
        await model.waitForPendingReplies()
        XCTAssertEqual(model.activeSessionID, currentID)
        XCTAssertEqual(model.settings.vocabulary, .complex)
        XCTAssertEqual(model.draft, "Do not erase this")
        XCTAssertFalse(model.messages.contains { $0.replyToMessageID == target.id })
        let archived = try XCTUnwrap(model.history.first { $0.id == firstID })
        XCTAssertEqual(archived.messages.last?.replyToMessageID, target.id)
        XCTAssertEqual(archived.settings.tone, .warm)
        XCTAssertNil(archived.pendingReply)
    }

    @MainActor
    func testSystemRequestChangesSettingsWithoutAnExtraPartnerTurnOrPracticeAttempt() async throws {
        let model = makeModel(ReplyProbe())
        model.suggestPrompt()
        XCTAssertTrue(model.startConversation())
        await model.waitForPendingReplies()
        model.toggleSystemMessageMode()
        model.draft = "请用简单词汇。"
        XCTAssertTrue(model.submitDraft())
        let request = try XCTUnwrap(model.messages.last)
        XCTAssertEqual(request.purpose, .systemAssistance)
        XCTAssertFalse(model.isSystemMessageMode)
        await model.waitForPendingReplies()
        XCTAssertEqual(model.messages.count, 3)
        XCTAssertEqual(model.messages.last?.senderRole, .system)
        XCTAssertEqual(model.messages.last?.replyToMessageID, request.id)
        XCTAssertEqual(model.settings.vocabulary, .simple)
        XCTAssertEqual(model.settings.tone, .casual)
        let report = try await model.statisticsSnapshot()
        XCTAssertEqual(report.overall.practiceAttempts, 0)
        XCTAssertTrue(model.textAnalyses.isEmpty)
    }

    @MainActor
    func testSystemResultPreservesSettingsChangedManuallyDuringTheRequest() async throws {
        let started = expectation(description: "System request is in flight")
        let probe = ReplyProbe(pauseAt: 2, onPause: { started.fulfill() })
        defer { Task { await probe.release() } }
        let model = makeModel(probe)
        model.suggestPrompt()
        XCTAssertTrue(model.startConversation())
        await model.waitForPendingReplies()
        model.toggleSystemMessageMode()
        model.draft = "请用简单词汇。"
        XCTAssertTrue(model.submitDraft())
        await fulfillment(of: [started], timeout: 2)
        model.settings.vocabulary = .complex
        model.settings.tone = .formal
        await probe.release()
        await model.waitForPendingReplies()
        XCTAssertEqual(model.settings.vocabulary, .complex)
        XCTAssertEqual(model.settings.tone, .formal)
        XCTAssertEqual(model.messages.last?.senderRole, .system)
    }

    @MainActor
    func testPendingRequestSurvivesRelaunchWithoutAutomaticPaidRetry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let probe = ReplyProbe(failAt: 2)
        let writer = ConversationViewModel.persistent(directory: directory, replyGenerator: { try await probe.respond($0) })
        writer.suggestPrompt()
        XCTAssertTrue(writer.startConversation())
        await writer.waitForPendingReplies()
        writer.draft = "I would like tea."
        XCTAssertTrue(writer.submitDraft())
        await writer.waitForPendingReplies()
        await writer.waitForPendingTextAnalyses()
        let id = try XCTUnwrap(writer.activeSessionID)
        let originalJob = try XCTUnwrap(writer.pendingReply)
        let nextProbe = ReplyProbe()
        let reader = ConversationViewModel.persistent(directory: directory, replyGenerator: { try await nextProbe.respond($0) })
        await reader.waitForPendingReplies()
        let callsBeforeRetry = await nextProbe.calls
        XCTAssertTrue(callsBeforeRetry.isEmpty)
        XCTAssertTrue(reader.openConversation(id))
        XCTAssertEqual(reader.pendingReply, originalJob)
        reader.retryReply()
        await reader.waitForPendingReplies()
        let calls = await nextProbe.calls
        XCTAssertEqual(calls, [originalJob.request])
        XCTAssertEqual(reader.messages.last?.id, originalJob.request.requestID)
        XCTAssertEqual(reader.textAnalyses.count, 1)
        XCTAssertNil(reader.pendingReply)
    }

    @MainActor
    func testWrongResponseIdentityCannotEnterHistoryAndFailureCanBeDismissed() async throws {
        let model = ConversationViewModel(history: [], replyGenerator: { request in
            ConversationReplyResponse(requestID: UUID().uuidString, conversationID: request.conversationID,
                replyToMessageID: request.replyToMessageID, kind: request.kind, text: "Wrong reply",
                settings: request.settings, model: "test", promptVersion: "test")
        })
        model.suggestPrompt()
        XCTAssertTrue(model.startConversation())
        await model.waitForPendingReplies()
        XCTAssertTrue(model.messages.isEmpty)
        XCTAssertNotNil(model.pendingReply?.failureMessage)
        model.dismissFailedReply()
        XCTAssertNil(model.pendingReply)
        model.draft = "Start again."
        XCTAssertTrue(model.submitDraft())
        await model.waitForPendingReplies()
        XCTAssertEqual(model.messages.count, 1)
        XCTAssertEqual(model.messages.last?.senderRole, .user)
    }

    @MainActor
    func testOverlongTextDoesNotCommitOrEraseTheDraft() async throws {
        let model = makeModel(ReplyProbe())
        model.suggestPrompt()
        XCTAssertTrue(model.startConversation())
        await model.waitForPendingReplies()
        let previous = model.messages
        model.draft = String(repeating: "a", count: 4001)
        XCTAssertFalse(model.submitDraft())
        XCTAssertEqual(model.messages, previous)
        XCTAssertEqual(model.draft.count, 4001)
        XCTAssertNotNil(model.replyIssue)
        XCTAssertNil(model.pendingReply)
    }

    @MainActor
    func testFailedLocalSaveDoesNotCallProviderOrClearTheDraft() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = ConversationViewModel.persistent(directory: directory)
        writer.suggestPrompt()
        XCTAssertTrue(writer.startConversation())
        let id = try XCTUnwrap(writer.activeSessionID)
        let probe = ReplyProbe()
        let store = try ConversationHistoryStore(directory: directory, allowsSave: false)
        let reader = ConversationViewModel.persistent(store: store, replyGenerator: { try await probe.respond($0) })
        XCTAssertTrue(reader.openConversation(id))
        reader.draft = "Keep this unsent text."
        XCTAssertFalse(reader.submitDraft())
        await reader.waitForPendingReplies()
        let calls = await probe.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(reader.draft, "Keep this unsent text.")
        XCTAssertEqual(reader.messages, writer.messages)
        XCTAssertNil(reader.pendingReply)
        XCTAssertNotNil(reader.storageIssue)
    }

    @MainActor
    func testReplySaveFailureRetainsTheRequestForWritableRecovery() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let failing = ReplyProbe(failAt: 1)
        let writer = ConversationViewModel.persistent(directory: directory, replyGenerator: { try await failing.respond($0) })
        writer.suggestPrompt()
        XCTAssertTrue(writer.startConversation())
        await writer.waitForPendingReplies()
        let id = try XCTUnwrap(writer.activeSessionID)
        let job = try XCTUnwrap(writer.pendingReply)
        let probe = ReplyProbe()
        let reader = ConversationViewModel.persistent(
            store: try ConversationHistoryStore(directory: directory, allowsSave: false),
            replyGenerator: { try await probe.respond($0) })
        XCTAssertTrue(reader.openConversation(id))
        reader.retryReply()
        await reader.waitForPendingReplies()
        XCTAssertEqual(reader.pendingReply?.request, job.request)
        XCTAssertTrue(reader.messages.isEmpty)
        XCTAssertNotNil(reader.storageIssue)
        let writable = ConversationViewModel.persistent(directory: directory, replyGenerator: { try await probe.respond($0) })
        XCTAssertTrue(writable.openConversation(id))
        writable.retryReply()
        await writable.waitForPendingReplies()
        XCTAssertEqual(writable.messages.count, 1)
        XCTAssertEqual(writable.messages.first?.id, job.request.requestID)
        XCTAssertNil(writable.pendingReply)
        let calls = await probe.calls
        XCTAssertEqual(calls, [job.request, job.request])
    }

    func testContextIsBoundedAndExcludesAudioReferences() throws {
        let id = UUID().uuidString
        var messages = (0..<60).map { _ in
            Message(conversationID: id, senderRole: .user, modality: .written,
                    content: .text(String(repeating: "a", count: 1000)))
        }
        let key = UUID().uuidString + ".caf"
        messages.append(Message(conversationID: id, senderRole: .user, modality: .spoken,
                                content: .audio(.init(storageKey: key, durationSeconds: 2))))
        let target = Message(conversationID: id, senderRole: .user, modality: .written, content: .text("My latest message."))
        messages.append(target)
        let session = ConversationSession(id: id, title: "Test", prompt: "Practice", messages: messages, settings: .init())
        let request = try ConversationReplyRequest(session: session, replyingTo: target)
        XCTAssertEqual(request.messages.last?.id, target.id)
        XCTAssertLessThanOrEqual(request.messages.count, 40)
        XCTAssertLessThanOrEqual(request.messages.reduce(0) { $0 + $1.text.utf16.count }, 24000)
        XCTAssertFalse(request.messages.contains { $0.id == messages[messages.count - 2].id })
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(request), as: UTF8.self).contains(key))
    }

    @MainActor
    private func makeModel(_ probe: ReplyProbe) -> ConversationViewModel {
        ConversationViewModel(history: [], replyGenerator: { try await probe.respond($0) })
    }
}

private actor ReplyProbe {
    private let failAt: Int?
    private let pauseAt: Int?
    private let onPause: @Sendable () -> Void
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    private(set) var calls: [ConversationReplyRequest] = []

    init(failAt: Int? = nil, pauseAt: Int? = nil, onPause: @escaping @Sendable () -> Void = {}) {
        self.failAt = failAt
        self.pauseAt = pauseAt
        self.onPause = onPause
    }

    func respond(_ request: ConversationReplyRequest) async throws -> ConversationReplyResponse {
        calls.append(request)
        let number = calls.count
        if number == pauseAt {
            onPause()
            if !released { await withCheckedContinuation { continuation = $0 } }
        }
        if number == failAt { throw ConversationReplyError.unavailable }
        var settings = request.settings
        if request.kind == .system { settings.vocabulary = .simple }
        return ConversationReplyResponse(requestID: request.requestID, conversationID: request.conversationID,
            replyToMessageID: request.replyToMessageID, kind: request.kind,
            text: request.kind == .system ? "好的，我会用更简单的词。" : "Welcome! What tea would you like?",
            settings: settings, model: "test-model", promptVersion: "test-v1")
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}
