import Foundation
import XCTest
@testable import XiaoLiao

final class TextAnalysisPipelineTests: XCTestCase {
    @MainActor
    func testCommittedTextAndEveryEditAutomaticallyPopulateTheDashboard() async throws {
        let model = makeConversation()
        let text = Array(repeating: "Run runs running.", count: 18).joined(separator: " ")
        model.draft = text
        XCTAssertTrue(model.submitDraft())
        let original = try XCTUnwrap(model.messages.last)
        model.selectMessage(original.id)
        model.perform(.edit, on: original.id)
        model.draft = text + " Again."
        XCTAssertTrue(model.submitDraft())
        let edit = try XCTUnwrap(model.messages.last)
        // No manual analysis API call: opening statistics waits for pending work.
        let report = try await model.statisticsSnapshot()
        XCTAssertEqual(model.textAnalyses.count, 2)
        XCTAssertEqual(Set(model.textAnalyses.map { $0.metadata.messageID }), [original.id, edit.id])
        XCTAssertEqual(report.overall.practiceAttempts, 2)
        XCTAssertEqual(report.overall.wordCount, 109)
        XCTAssertEqual(report.overall.sentenceCount, 37)
        XCTAssertNotNil(report.overall.mattr)
        XCTAssertEqual(report.overall.distinctWordForms, 4)
        XCTAssertEqual(report.vocabularyHistory.first { $0.wordForm == "run" }?.firstMessageID, original.id)
        XCTAssertEqual(report.vocabularyHistory.first { $0.wordForm == "again" }?.firstMessageID, edit.id)
        XCTAssertEqual(report.vocabularyHistory.first { $0.wordForm == "run" }?.firstUsedAt, original.createdAt)
        XCTAssertTrue(model.grammarObservations.isEmpty)
        XCTAssertTrue(model.vocabularyObservations.isEmpty)
        XCTAssertNil(report.overall.clauseCount)
        XCTAssertNil(report.overall.clausesPerSentence)
        XCTAssertTrue(report.overall.grammar.allSatisfy { $0.accuracy == nil })
    }

    @MainActor
    func testDelayedResultsMergeIntoTheirOwnConversationWithoutUndoingNewerState() async throws {
        let started = expectation(description: "Original version is being analyzed")
        let probe = AnalyzerProbe(pausesFirst: true, onFirstCall: { started.fulfill() })
        defer { Task { await probe.release() } }
        let model = makeConversation(analyzer: { try await probe.analyze($0) })
        let oldID = try XCTUnwrap(model.activeSessionID)
        model.draft = "I like turtles."
        XCTAssertTrue(model.submitDraft())
        let original = try XCTUnwrap(model.messages.last)
        await fulfillment(of: [started], timeout: 2)
        // Repeated triggers must not enqueue the in-flight original twice.
        model.retryPendingTextAnalyses()
        model.retryPendingTextAnalyses()
        model.selectMessage(original.id)
        model.perform(.edit, on: original.id)
        model.draft = "I love sea turtles."
        XCTAssertTrue(model.submitDraft())
        let edited = try XCTUnwrap(model.messages.last)
        model.settings.tone = .warm
        model.prepareNewConversation()
        model.prompt = "A different conversation"
        XCTAssertTrue(model.startConversation())
        let currentID = model.activeSessionID
        let currentMessages = model.messages
        model.settings.tone = .formal
        model.draft = "Keep this unsent draft"
        model.storageIssue = .init(message: "Existing warning")
        await probe.release()
        await model.waitForPendingTextAnalyses()
        let archived = try XCTUnwrap(model.history.first { $0.id == oldID })
        XCTAssertEqual(archived.settings.tone, .warm)
        XCTAssertEqual(archived.latestMessages.last, edited)
        XCTAssertEqual(Set(archived.textAnalyses.map { $0.metadata.messageID }), [original.id, edited.id])
        XCTAssertEqual(model.activeSessionID, currentID)
        XCTAssertEqual(model.messages, currentMessages)
        XCTAssertEqual(model.draft, "Keep this unsent draft")
        XCTAssertEqual(model.settings.tone, .formal)
        XCTAssertTrue(model.textAnalyses.isEmpty)
        XCTAssertEqual(model.storageIssue?.message, "Existing warning")
        let calls = await probe.calls
        XCTAssertEqual(calls, [original.id, edited.id])
    }

    @MainActor
    func testExtractionFailureLeavesSendSuccessfulAndRetriesOnceOnALaterTrigger() async throws {
        let probe = AnalyzerProbe(firstResult: .failure)
        let model = makeConversation(analyzer: { try await probe.analyze($0) })
        model.draft = "Run runs running."
        XCTAssertTrue(model.submitDraft())
        let sent = try XCTUnwrap(model.messages.last)
        await model.waitForPendingTextAnalyses()
        XCTAssertEqual(model.messages.last, sent)
        XCTAssertTrue(model.draft.isEmpty)
        XCTAssertTrue(model.textAnalyses.isEmpty)
        XCTAssertNil(model.storageIssue)
        let firstCalls = await probe.calls
        XCTAssertEqual(firstCalls, [sent.id])
        model.retryPendingTextAnalyses()
        await model.waitForPendingTextAnalyses()
        let saved = model.textAnalyses
        XCTAssertEqual(saved.count, 1)
        model.retryPendingTextAnalyses()
        await model.waitForPendingTextAnalyses()
        XCTAssertEqual(model.textAnalyses, saved)
        let allCalls = await probe.calls
        XCTAssertEqual(allCalls, [sent.id, sent.id])
    }

    @MainActor
    func testNilAndMisidentifiedResultsRemainPendingRatherThanBeingStored() async throws {
        for behavior in [AnalyzerProbe.FirstResult.missing, .wrongIdentity] {
            let probe = AnalyzerProbe(firstResult: behavior)
            let model = makeConversation(analyzer: { try await probe.analyze($0) })
            model.draft = "A real message."
            XCTAssertTrue(model.submitDraft())
            await model.waitForPendingTextAnalyses()
            XCTAssertTrue(model.textAnalyses.isEmpty)
            XCTAssertNil(model.storageIssue)
            let report = try await model.statisticsSnapshot()
            XCTAssertEqual(report.overall.textAnalyzedAttempts, 1)
            XCTAssertEqual(model.textAnalyses.count, 1)
            let calls = await probe.calls
            XCTAssertEqual(calls.count, 2)
        }
    }

    @MainActor
    func testMissingResultsSurviveRelaunchAndAnalysisWriteFailurePreservesCommittedMessages() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessionID: String
        let sent: Message
        do {
            let writer = ConversationViewModel.persistent(directory: directory, textAnalyzer: { _ in nil })
            writer.suggestPrompt()
            XCTAssertTrue(writer.startConversation())
            sessionID = try XCTUnwrap(writer.activeSessionID)
            writer.draft = "Run runs running."
            XCTAssertTrue(writer.submitDraft())
            sent = try XCTUnwrap(writer.messages.last)
            await writer.waitForPendingTextAnalyses()
            XCTAssertTrue(writer.textAnalyses.isEmpty)
        }
        do {
            let reader = ConversationViewModel.persistent(store: try ConversationHistoryStore(directory: directory, allowsSave: false))
            await reader.waitForPendingTextAnalyses()
            XCTAssertTrue(reader.openConversation(sessionID))
            XCTAssertEqual(reader.messages.last, sent)
            XCTAssertTrue(reader.textAnalyses.isEmpty)
            XCTAssertNil(reader.storageIssue)
            let partial = try await reader.statisticsSnapshot()
            XCTAssertEqual(partial.overall.practiceAttempts, 1)
            XCTAssertNil(partial.overall.sentenceCount)
            XCTAssertNil(reader.storageIssue)
        }
        let recovered = ConversationViewModel.persistent(directory: directory)
        let report = try await recovered.statisticsSnapshot()
        XCTAssertTrue(recovered.openConversation(sessionID))
        XCTAssertEqual(recovered.messages.last, sent)
        XCTAssertEqual(recovered.textAnalyses.count, 1)
        XCTAssertEqual(report.overall.wordCount, 3)
        XCTAssertEqual(report.overall.sentenceCount, 1)
        let existing = recovered.textAnalyses
        let probe = AnalyzerProbe()
        let nextLaunch = ConversationViewModel.persistent(directory: directory, textAnalyzer: { try await probe.analyze($0) })
        await nextLaunch.waitForPendingTextAnalyses()
        XCTAssertTrue(nextLaunch.openConversation(sessionID))
        XCTAssertEqual(nextLaunch.textAnalyses, existing)
        let calls = await probe.calls
        XCTAssertTrue(calls.isEmpty)
    }

    @MainActor
    func testAFailedChatSaveNeverEnqueuesTheUncommittedDraft() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id: String
        do {
            let writer = ConversationViewModel.persistent(directory: directory)
            writer.suggestPrompt()
            XCTAssertTrue(writer.startConversation())
            id = try XCTUnwrap(writer.activeSessionID)
        }
        let probe = AnalyzerProbe()
        let source = ConversationViewModel.persistent(store: try ConversationHistoryStore(directory: directory, allowsSave: false),
                                                      textAnalyzer: { try await probe.analyze($0) })
        XCTAssertTrue(source.openConversation(id))
        let before = source.messageVersions
        source.draft = "Keep this unsent text"
        XCTAssertFalse(source.submitDraft())
        await source.waitForPendingTextAnalyses()
        XCTAssertEqual(source.messageVersions, before)
        XCTAssertEqual(source.draft, "Keep this unsent text")
        XCTAssertTrue(source.textAnalyses.isEmpty)
        let calls = await probe.calls
        XCTAssertTrue(calls.isEmpty)
    }

    @MainActor
    func testOnlyCommittedLearnerTextAndTextBackedSpokenEditsAreEligible() async {
        func message(_ id: String, role: Message.SenderRole = .user, purpose: Message.Purpose = .conversationPractice,
                     status: Message.Status? = .complete, origin: Message.Origin? = .interaction) -> Message {
            Message(id: id, conversationID: "eligibility", senderRole: role, purpose: purpose, modality: .written,
                    content: .text("A message."), status: status, origin: origin)
        }
        let typed = message("typed")
        let spoken = Message(id: "spoken-text", conversationID: "eligibility", senderRole: .user, modality: .spoken,
                             content: .text("Edited spoken text."), transcription: .init(text: "Edited spoken text.", confidence: nil))
        let audio = Message(id: "audio", conversationID: "eligibility", senderRole: .user, modality: .spoken,
                            content: .audio(.init(storageKey: UUID().uuidString + ".caf", durationSeconds: 1)))
        let session = ConversationSession(id: "eligibility", title: "test", prompt: "test", messages: [typed, spoken, audio,
            message("fixture", origin: .fixture), message("legacy", origin: nil), message("pending", status: .pending),
            message("failed", status: .failed), message("unknown-status", status: nil), message("partner", role: .aiPartner),
            message("request", purpose: .systemAssistance), message("system", role: .system, purpose: .systemAssistance)], settings: .init())
        let probe = AnalyzerProbe()
        let model = ConversationViewModel(history: [session], textAnalyzer: { try await probe.analyze($0) })
        await model.waitForPendingTextAnalyses()
        let calls = await probe.calls
        XCTAssertEqual(Set(calls), [typed.id, spoken.id])
        XCTAssertEqual(model.history[0].textAnalyses.count, 2)
        XCTAssertTrue(model.history[0].grammarObservations.isEmpty)
        XCTAssertTrue(model.history[0].vocabularyObservations.isEmpty)
    }

    @MainActor
    func testLateAutomaticResultCannotReplaceAnAlreadySuppliedRicherAnalysis() async throws {
        let started = expectation(description: "Local extraction started")
        let probe = AnalyzerProbe(pausesFirst: true, onFirstCall: { started.fulfill() })
        defer { Task { await probe.release() } }
        let model = makeConversation(analyzer: { try await probe.analyze($0) })
        model.draft = "I like turtles because they are interesting."
        XCTAssertTrue(model.submitDraft())
        let sent = try XCTUnwrap(model.messages.last)
        await fulfillment(of: [started], timeout: 2)
        let base = try XCTUnwrap(LocalTextAnalyzer.analyze(sent))
        let richer = MessageTextAnalysis(metadata: base.metadata, normalizationVersion: base.normalizationVersion,
            words: base.words, sentenceSpans: base.sentenceSpans,
            clauses: .init(count: 2, provenance: .init(method: .manual, evaluatorID: "test-only", evaluatorVersion: "1",
                                                     rubricVersion: "1", taxonomyVersion: "1")))
        XCTAssertTrue(model.recordTextAnalysis(richer))
        await probe.release()
        await model.waitForPendingTextAnalyses()
        XCTAssertEqual(model.textAnalyses, [richer])
    }

    @MainActor
    func testCancellingADashboardRequestDoesNotCancelCommittedMessageAnalysis() async throws {
        let started = expectation(description: "Local extraction started")
        let probe = AnalyzerProbe(pausesFirst: true, onFirstCall: { started.fulfill() })
        defer { Task { await probe.release() } }
        let model = makeConversation(analyzer: { try await probe.analyze($0) })
        model.draft = "Run runs running."
        XCTAssertTrue(model.submitDraft())
        let request = Task { @MainActor in try await model.statisticsSnapshot() }
        await fulfillment(of: [started], timeout: 2)
        request.cancel()
        await probe.release()
        do {
            _ = try await request.value
            XCTFail("Cancelled dashboard requests should not publish a snapshot")
        } catch is CancellationError {
            // The independently owned message-analysis worker still completes.
        }
        await model.waitForPendingTextAnalyses()
        XCTAssertEqual(model.textAnalyses.count, 1)
        XCTAssertEqual(model.messages.last?.content, .text("Run runs running."))
    }

    @MainActor
    private func makeConversation(analyzer: ConversationViewModel.TextAnalyzer? = nil) -> ConversationViewModel {
        let model = ConversationViewModel(history: [], textAnalyzer: analyzer)
        model.suggestPrompt()
        XCTAssertTrue(model.startConversation())
        return model
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private actor AnalyzerProbe {
    enum FirstResult: Sendable { case success, failure, missing, wrongIdentity }
    enum Failure: Error { case expected }
    private let firstResult: FirstResult
    private let pausesFirst: Bool
    private let onFirstCall: @Sendable () -> Void
    private var isReleased = false
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var calls: [String] = []

    init(firstResult: FirstResult = .success, pausesFirst: Bool = false, onFirstCall: @escaping @Sendable () -> Void = {}) {
        self.firstResult = firstResult
        self.pausesFirst = pausesFirst
        self.onFirstCall = onFirstCall
    }

    func analyze(_ message: Message) async throws -> MessageTextAnalysis? {
        calls.append(message.id)
        if calls.count == 1 {
            onFirstCall()
            if pausesFirst && !isReleased { await withCheckedContinuation { continuation = $0 } }
            switch firstResult {
            case .failure: throw Failure.expected
            case .missing: return nil
            case .wrongIdentity:
                let other = Message(id: "wrong-record", conversationID: message.conversationID, senderRole: .user,
                                    modality: .written, content: message.content)
                return try LocalTextAnalyzer.analyze(other)
            case .success: break
            }
        }
        return try LocalTextAnalyzer.analyze(message)
    }

    func release() {
        isReleased = true
        continuation?.resume()
        continuation = nil
    }
}
