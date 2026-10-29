import Foundation
import XCTest
@testable import XiaoLiao

final class GrammarEvaluationTests: XCTestCase {
    @MainActor
    func testNewTextAndEveryEditReceiveSeparateSavedObservationsAndAccuracy() async throws {
        let probe = GrammarProbe()
        let model = makeModel(probe)
        model.suggestPrompt()
        XCTAssertTrue(model.startConversation())
        model.draft = "She go every day."
        XCTAssertTrue(model.submitDraft())
        let original = try XCTUnwrap(model.messages.last)
        XCTAssertEqual(model.pendingGrammarCount, 1)
        await model.waitForPendingGrammarEvaluations()
        model.selectMessage(original.id)
        model.perform(.edit, on: original.id)
        model.draft = "She goes every day."
        XCTAssertTrue(model.submitDraft())
        let edit = try XCTUnwrap(model.messages.last)
        await model.waitForPendingGrammarEvaluations()
        XCTAssertEqual(model.grammarObservations.count, 2)
        XCTAssertEqual(Set(model.grammarObservations.map { $0.metadata.messageID }), [original.id, edit.id])
        XCTAssertEqual(model.grammarObservations.map { $0.metadata.messageRevision }, [1, 2])
        XCTAssertEqual(model.grammarObservations.first?.metadata.provenance.method, .languageModel)
        XCTAssertEqual(model.grammarObservations.first?.metadata.provenance.rubricVersion, "grammar-v1")
        let report = try await model.statisticsSnapshot()
        let agreement = try XCTUnwrap(report.overall.grammar.first { $0.category == .subjectVerbAgreement })
        XCTAssertEqual(agreement.correct, 1)
        XCTAssertEqual(agreement.incorrect, 1)
        XCTAssertEqual(agreement.accuracy, 0.5)
        XCTAssertEqual(report.overall.practiceAttempts, 2)
        XCTAssertEqual(report.overall.grammarEvaluatedAttempts, 2)
        XCTAssertEqual(model.pendingGrammarCount, 0)
        XCTAssertEqual(model.failedGrammarCount, 0)
        XCTAssertTrue(model.history.first?.grammarEvaluationJobs.isEmpty == true)
    }

    @MainActor
    func testOldHistoryIsNotBackfilledButANewEditOfAnOldMessageIsEvaluated() async throws {
        let session = eligibleSession()
        let probe = GrammarProbe()
        let model = ConversationViewModel(history: [session], grammarEvaluator: { try await probe.evaluate($0) })
        await model.waitForPendingGrammarEvaluations()
        let before = await probe.calls
        XCTAssertTrue(before.isEmpty)
        XCTAssertTrue(model.openConversation(session.id))
        let original = try XCTUnwrap(model.messages.last)
        model.selectMessage(original.id)
        model.perform(.edit, on: original.id)
        model.draft = "She goes every day."
        XCTAssertTrue(model.submitDraft())
        await model.waitForPendingGrammarEvaluations()
        XCTAssertEqual(model.grammarObservations.count, 1)
        XCTAssertEqual(model.grammarObservations.first?.metadata.messageRevision, 2)
        XCTAssertFalse(model.grammarObservations.contains { $0.metadata.messageID == original.id })
        let calls = await probe.calls
        XCTAssertEqual(calls.count, 1)
    }

    @MainActor
    func testDelayedResultsPreserveEditsAndTheActiveConversationDraftAndSettings() async throws {
        let started = expectation(description: "Grammar is in flight")
        let probe = GrammarProbe(pauseFirst: true, onFirst: { started.fulfill() })
        defer { Task { await probe.release() } }
        let model = makeModel(probe)
        model.suggestPrompt()
        XCTAssertTrue(model.startConversation())
        let originalSessionID = try XCTUnwrap(model.activeSessionID)
        model.draft = "She go every day."
        XCTAssertTrue(model.submitDraft())
        let original = try XCTUnwrap(model.messages.last)
        await fulfillment(of: [started], timeout: 2)
        // Grammar never locks editing or sending.
        model.selectMessage(original.id)
        model.perform(.edit, on: original.id)
        model.draft = "She goes every day."
        XCTAssertTrue(model.submitDraft())
        model.settings.tone = .warm
        model.prepareNewConversation()
        model.prompt = "Another topic"
        XCTAssertTrue(model.startConversation())
        let currentID = model.activeSessionID
        let currentMessages = model.messages
        model.settings.tone = .formal
        model.draft = "Keep this draft"
        model.storageIssue = .init(message: "Existing warning")
        await probe.release()
        await model.waitForPendingGrammarEvaluations()
        let archived = try XCTUnwrap(model.history.first { $0.id == originalSessionID })
        XCTAssertEqual(archived.grammarObservations.count, 2)
        XCTAssertEqual(archived.settings.tone, .warm)
        XCTAssertEqual(model.activeSessionID, currentID)
        XCTAssertEqual(model.messages, currentMessages)
        XCTAssertEqual(model.settings.tone, .formal)
        XCTAssertEqual(model.draft, "Keep this draft")
        XCTAssertTrue(model.grammarObservations.isEmpty)
        XCTAssertEqual(model.storageIssue?.message, "Existing warning")
    }

    @MainActor
    func testFailuresNeverBecomeErrorsAndOnlyExplicitRetryResendsTheSameRequest() async throws {
        let probe = GrammarProbe(failFirst: true)
        let model = makeModel(probe)
        model.suggestPrompt()
        XCTAssertTrue(model.startConversation())
        model.draft = "She go every day."
        XCTAssertTrue(model.submitDraft())
        let sent = model.messages.last
        await model.waitForPendingGrammarEvaluations()
        XCTAssertEqual(model.failedGrammarCount, 1)
        XCTAssertEqual(model.messages.last, sent)
        XCTAssertTrue(model.draft.isEmpty)
        XCTAssertTrue(model.grammarObservations.isEmpty)
        XCTAssertNil(model.storageIssue)
        model.resumeQueuedGrammarEvaluations()
        model.resumeQueuedGrammarEvaluations()
        let report = try await model.statisticsSnapshot()
        XCTAssertEqual(report.overall.grammarEvaluatedAttempts, 0)
        XCTAssertTrue(report.overall.grammar.allSatisfy { $0.accuracy == nil })
        let before = await probe.calls
        XCTAssertEqual(before.count, 1)
        model.retryFailedGrammarEvaluations()
        model.retryFailedGrammarEvaluations()
        await model.waitForPendingGrammarEvaluations()
        let calls = await probe.calls
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[0], calls[1])
        XCTAssertEqual(model.grammarObservations.first?.id, calls[0].requestID)
        XCTAssertEqual(model.failedGrammarCount, 0)
    }

    @MainActor
    func testInterruptedAttemptSurvivesRelaunchAndRequiresExplicitRetry() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var session = eligibleSession()
        let request = try XCTUnwrap(GrammarEvaluationRequest(message: session.messages[0]))
        session.grammarEvaluationJobs = [.init(request: request, state: .attempted)]
        let store = try ConversationHistoryStore(directory: directory)
        _ = try store.load()
        _ = try store.save(session)
        let probe = GrammarProbe()
        let model = ConversationViewModel.persistent(directory: directory, grammarEvaluator: { try await probe.evaluate($0) })
        await model.waitForPendingGrammarEvaluations()
        XCTAssertEqual(model.failedGrammarCount, 1)
        let before = await probe.calls
        XCTAssertTrue(before.isEmpty)
        model.retryFailedGrammarEvaluations()
        await model.waitForPendingGrammarEvaluations()
        let calls = await probe.calls
        XCTAssertEqual(calls, [request])
        let reloaded = ConversationViewModel.persistent(directory: directory, grammarEvaluator: { try await probe.evaluate($0) })
        await reloaded.waitForPendingGrammarEvaluations()
        XCTAssertEqual(reloaded.history.first?.grammarObservations.count, 1)
        XCTAssertTrue(reloaded.history.first?.grammarEvaluationJobs.isEmpty == true)
        let after = await probe.calls
        XCTAssertEqual(after.count, 1)
    }

    @MainActor
    func testUnattemptedQueuedWorkResumesButOtherOldMessagesStayUnevaluated() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var session = eligibleSession()
        let queued = Message(conversationID: session.id, senderRole: .user, modality: .written, content: .text("She goes every day."))
        session.messages.append(queued)
        let request = try XCTUnwrap(GrammarEvaluationRequest(message: queued))
        session.grammarEvaluationJobs = [.init(request: request)]
        let store = try ConversationHistoryStore(directory: directory)
        _ = try store.load()
        _ = try store.save(session)
        let probe = GrammarProbe()
        let model = ConversationViewModel.persistent(directory: directory, grammarEvaluator: { try await probe.evaluate($0) })
        await model.waitForPendingGrammarEvaluations()
        XCTAssertEqual(model.history.first?.grammarObservations.map { $0.metadata.messageID }, [queued.id])
        let calls = await probe.calls
        XCTAssertEqual(calls, [request])
    }

    @MainActor
    func testFailedChatSaveKeepsTheDraftAndDoesNotQueueGrammar() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = eligibleSession()
        let store = try ConversationHistoryStore(directory: directory)
        _ = try store.load()
        _ = try store.save(session)
        let probe = GrammarProbe()
        let reader = ConversationViewModel.persistent(store: try ConversationHistoryStore(directory: directory, allowsSave: false),
                                                       grammarEvaluator: { try await probe.evaluate($0) })
        XCTAssertTrue(reader.openConversation(session.id))
        reader.draft = "She goes every day."
        XCTAssertFalse(reader.submitDraft())
        await reader.waitForPendingGrammarEvaluations()
        XCTAssertEqual(reader.draft, "She goes every day.")
        XCTAssertTrue(reader.history.first?.grammarEvaluationJobs.isEmpty == true)
        XCTAssertEqual(reader.messages, session.messages)
        let calls = await probe.calls
        XCTAssertTrue(calls.isEmpty)
    }

    @MainActor
    func testReadOnlyProgressSaveDoesNotMakeAPaidCallAndWritableRelaunchRecovers() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var session = eligibleSession()
        session.grammarEvaluationJobs = [.init(request: try XCTUnwrap(GrammarEvaluationRequest(message: session.messages[0])))]
        let writer = try ConversationHistoryStore(directory: directory)
        _ = try writer.load()
        _ = try writer.save(session)
        let probe = GrammarProbe()
        let reader = ConversationViewModel.persistent(store: try ConversationHistoryStore(directory: directory, allowsSave: false),
                                                       grammarEvaluator: { try await probe.evaluate($0) })
        await reader.waitForPendingGrammarEvaluations()
        let noCalls = await probe.calls
        XCTAssertTrue(noCalls.isEmpty)
        XCTAssertNotNil(reader.grammarQueueIssue)
        XCTAssertNil(reader.storageIssue)
        XCTAssertEqual(reader.history.first?.messages, session.messages)
        XCTAssertTrue(reader.history.first?.grammarObservations.isEmpty == true)
        let recovered = ConversationViewModel.persistent(directory: directory, grammarEvaluator: { try await probe.evaluate($0) })
        await recovered.waitForPendingGrammarEvaluations()
        XCTAssertEqual(recovered.history.first?.grammarObservations.count, 1)
    }

    @MainActor
    func testInvalidIdentityOrUnicodeSpanCannotPopulateStatistics() async throws {
        for invalid in [GrammarProbe.Invalid.identity, .span] {
            let probe = GrammarProbe(invalid: invalid)
            let model = makeModel(probe)
            model.suggestPrompt()
            XCTAssertTrue(model.startConversation())
            model.draft = "🐢 She go every day."
            XCTAssertTrue(model.submitDraft())
            await model.waitForPendingGrammarEvaluations()
            XCTAssertTrue(model.grammarObservations.isEmpty)
            XCTAssertEqual(model.failedGrammarCount, 1)
            let snapshot = try await model.statisticsSnapshot()
            XCTAssertEqual(snapshot.overall.grammarEvaluatedAttempts, 0)
        }
    }

    @MainActor
    func testManualResultWinsOverADelayedAutomaticResult() async throws {
        let started = expectation(description: "Grammar in flight")
        let probe = GrammarProbe(pauseFirst: true, onFirst: { started.fulfill() })
        defer { Task { await probe.release() } }
        let model = makeModel(probe)
        model.suggestPrompt()
        XCTAssertTrue(model.startConversation())
        model.draft = "She go every day."
        XCTAssertTrue(model.submitDraft())
        let sent = try XCTUnwrap(model.messages.last)
        await fulfillment(of: [started], timeout: 2)
        let manual = GrammarObservation(metadata: .init(id: UUID().uuidString, messageID: sent.id,
            conversationID: sent.conversationID, messageRevision: 1, textSource: .messageText, evaluatedAt: Date(),
            provenance: .init(method: .manual, evaluatorID: "reviewer", evaluatorVersion: "1", rubricVersion: "review", taxonomyVersion: "1"), confidence: nil), opportunities: [])
        XCTAssertTrue(model.recordGrammarObservation(manual))
        await probe.release()
        await model.waitForPendingGrammarEvaluations()
        XCTAssertEqual(model.grammarObservations, [manual])
        XCTAssertTrue(model.history.first?.grammarEvaluationJobs.isEmpty == true)
    }

    @MainActor
    func testSystemMessagesAndFixturesNeverQueueAndEmptyEvaluationsStayUnknown() async throws {
        let probe = GrammarProbe()
        let model = makeModel(probe)
        model.suggestPrompt()
        XCTAssertTrue(model.startConversation())
        model.toggleSystemMessageMode()
        model.draft = "你能用更简单的词吗？"
        XCTAssertTrue(model.submitDraft())
        await model.waitForPendingGrammarEvaluations()
        let noCalls = await probe.calls
        XCTAssertTrue(noCalls.isEmpty)
        model.draft = "Thanks!"
        XCTAssertTrue(model.submitDraft())
        await model.waitForPendingGrammarEvaluations()
        XCTAssertEqual(model.grammarObservations.count, 1)
        XCTAssertTrue(model.grammarObservations[0].opportunities.isEmpty)
        let report = try await model.statisticsSnapshot()
        XCTAssertEqual(report.overall.grammarEvaluatedAttempts, 1)
        XCTAssertTrue(report.overall.grammar.allSatisfy { $0.accuracy == nil })
    }

    @MainActor
    func testSlowGrammarDoesNotBlockPartnerRepliesOrFurtherMessages() async throws {
        let started = expectation(description: "Grammar in flight")
        let probe = GrammarProbe(pauseFirst: true, onFirst: { started.fulfill() })
        defer { Task { await probe.release() } }
        let model = ConversationViewModel(history: [], replyGenerator: { request in
            .init(requestID: request.requestID, conversationID: request.conversationID, replyToMessageID: request.replyToMessageID,
                  kind: request.kind, text: "Hello!", settings: request.settings, model: "test", promptVersion: "test")
        }, grammarEvaluator: { try await probe.evaluate($0) })
        model.suggestPrompt()
        XCTAssertTrue(model.startConversation())
        await model.waitForPendingReplies()
        model.draft = "She go every day."
        XCTAssertTrue(model.submitDraft())
        await fulfillment(of: [started], timeout: 2)
        await model.waitForPendingReplies()
        XCTAssertTrue(model.canSubmitMessage)
        XCTAssertEqual(model.messages.last?.senderRole, .aiPartner)
        XCTAssertTrue(model.grammarObservations.isEmpty)
        // Statistics returns current coverage without waiting for the network.
        let partial = try await model.statisticsSnapshot()
        XCTAssertEqual(partial.overall.grammarEvaluatedAttempts, 0)
        model.draft = "She goes every day."
        XCTAssertTrue(model.submitDraft())
        await model.waitForPendingReplies()
        await probe.release()
        await model.waitForPendingGrammarEvaluations()
        XCTAssertEqual(model.grammarObservations.count, 2)
    }

    @MainActor
    private func makeModel(_ probe: GrammarProbe) -> ConversationViewModel {
        ConversationViewModel(history: [], grammarEvaluator: { try await probe.evaluate($0) })
    }

    private func eligibleSession() -> ConversationSession {
        let id = UUID().uuidString
        return ConversationSession(id: id, title: "Test", prompt: "Practice", messages: [
            Message(conversationID: id, senderRole: .user, modality: .written, content: .text("She go every day."))
        ], settings: .init())
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private actor GrammarProbe {
    enum Invalid: Equatable, Sendable { case none, identity, span }
    private let pauseFirst: Bool
    private let failFirst: Bool
    private let invalid: Invalid
    private let onFirst: @Sendable () -> Void
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    private(set) var calls: [GrammarEvaluationRequest] = []

    init(pauseFirst: Bool = false, failFirst: Bool = false, invalid: Invalid = .none,
         onFirst: @escaping @Sendable () -> Void = {}) {
        self.pauseFirst = pauseFirst
        self.failFirst = failFirst
        self.invalid = invalid
        self.onFirst = onFirst
    }

    func evaluate(_ request: GrammarEvaluationRequest) async throws -> GrammarEvaluationResponse {
        calls.append(request)
        let first = calls.count == 1
        if first {
            onFirst()
            if pauseFirst && !released { await withCheckedContinuation { continuation = $0 } }
            if failFirst { throw ConversationReplyError.unavailable }
        }
        let correct = request.text.contains("goes")
        let evidence = correct ? "goes" : "go"
        let span = (request.text as NSString).range(of: evidence)
        let opportunities: [GrammarEvaluationResponse.Opportunity]
        if span.location == NSNotFound { opportunities = [] }
        else {
            opportunities = [.init(id: UUID().uuidString, category: .init(categoryID: "subject-verb-agreement", subcategoryID: nil),
                textSpan: .init(startUTF16: invalid == .span ? 1 : span.location, lengthUTF16: invalid == .span ? 1 : span.length),
                originalText: evidence, outcome: correct ? .correct : .incorrect, suggestedCorrection: correct ? nil : "goes",
                explanation: correct ? nil : "主语是第三人称单数。", confidence: nil)]
        }
        return .init(requestID: invalid == .identity ? UUID().uuidString : request.requestID,
            conversationID: request.conversationID, messageID: request.messageID, messageRevision: request.messageRevision,
            textSource: request.textSource, rubricVersion: "grammar-v1", taxonomyVersion: "grammar-five-v1", model: "test-model",
            evaluatedAtSeconds: Date().timeIntervalSince1970, opportunities: opportunities)
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}
