import AVFoundation
import Foundation
import XCTest
@testable import XiaoLiao

final class SpeechTranscriptionTests: XCTestCase {
    @MainActor
    func testRecordingBecomesOneSpokenPracticeAttemptWithRepliesAndStatistics() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let probe = SpeechProbe()
        let model = await liveModel(probe)
        let sessionID = try XCTUnwrap(model.activeSessionID)
        let clip = try makeClip(in: directory)
        XCTAssertTrue(model.commitRecording(clip, in: sessionID))
        let original = try XCTUnwrap(model.messages.last)
        XCTAssertNil(original.transcription)
        XCTAssertNotNil(model.pendingTranscription)
        XCTAssertFalse(model.canSubmitMessage)
        await finish(model)
        let spoken = try XCTUnwrap(model.messageVersions.first { $0.id == original.id })
        XCTAssertEqual(spoken.transcription?.text, "I like green tea.")
        XCTAssertNil(spoken.transcription?.confidence)
        XCTAssertEqual(spoken.modality, .spoken)
        XCTAssertEqual(spoken.content, original.content)
        XCTAssertEqual(spoken.createdAt, original.createdAt)
        XCTAssertEqual(spoken.logicalMessageID, original.logicalMessageID)
        XCTAssertEqual(spoken.revision, 1)
        XCTAssertEqual(model.messages.filter { $0.senderRole == .user }.count, 1)
        XCTAssertEqual(model.messages.last?.replyToMessageID, spoken.id)
        XCTAssertEqual(model.audioClip(for: spoken), clip)
        XCTAssertTrue(model.canSubmitMessage)
        let report = try await model.statisticsSnapshot()
        XCTAssertEqual(report.overall.practiceAttempts, 1)
        XCTAssertEqual(report.overall.wordCount, 4)
        XCTAssertEqual(report.overall.sentenceCount, 1)
        XCTAssertEqual(report.overall.grammarEvaluatedAttempts, 1)
        XCTAssertEqual(model.textAnalyses.first?.metadata.textSource, .speechTranscription)
        XCTAssertEqual(model.grammarObservations.first?.metadata.textSource, .speechTranscription)
        let replies = await probe.replyRequests
        XCTAssertEqual(replies.count, 2)
        XCTAssertEqual(replies.last?.messages.last?.text, "I like green tea.")
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(replies.last!), as: UTF8.self).contains(".caf"))
    }

    @MainActor
    func testFailureRetainsPlayableAudioAndRetryDoesNotDuplicatePracticeOrReplies() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let probe = SpeechProbe(failFirst: true)
        let model = await liveModel(probe)
        let clip = try makeClip(in: directory)
        XCTAssertTrue(model.commitRecording(clip, in: try XCTUnwrap(model.activeSessionID)))
        let sent = try XCTUnwrap(model.messages.last)
        await model.waitForPendingTranscriptions()
        let jobID = try XCTUnwrap(model.pendingTranscription?.id)
        XCTAssertEqual(model.pendingTranscription?.state, .failed)
        XCTAssertNotNil(model.pendingResponseFailure)
        XCTAssertNil(model.messages.last?.transcription)
        XCTAssertTrue(model.isAvailable(.play, for: sent))
        XCTAssertTrue(FileManager.default.fileExists(atPath: clip.url.path))
        let firstReplies = await probe.replyRequests
        XCTAssertEqual(firstReplies.count, 1)
        XCTAssertTrue(model.grammarObservations.isEmpty)
        model.resumeQueuedTranscriptions()
        let before = await probe.speechURLs
        XCTAssertEqual(before.count, 1)
        model.retryReply()
        XCTAssertEqual(model.pendingTranscription?.id, jobID)
        model.retryReply()
        await finish(model)
        let after = await probe.speechURLs
        XCTAssertEqual(after, [clip.url, clip.url])
        XCTAssertNil(model.pendingTranscription)
        XCTAssertEqual(model.messages.filter { $0.senderRole == .user }.count, 1)
        let replies = await probe.replyRequests
        XCTAssertEqual(replies.count, 2)
        XCTAssertEqual(model.grammarObservations.count, 1)
    }

    @MainActor
    func testLateTranscriptAndReplyStayWithTheirConversation() async throws {
        let started = expectation(description: "Recognition started")
        let probe = SpeechProbe(pauseFirst: true, onFirst: { started.fulfill() })
        defer { Task { await probe.release() } }
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = await liveModel(probe)
        let oldID = try XCTUnwrap(model.activeSessionID)
        XCTAssertTrue(model.commitRecording(try makeClip(in: directory), in: oldID))
        let recordedID = try XCTUnwrap(model.messages.last?.id)
        await fulfillment(of: [started], timeout: 2)
        model.settings.tone = .warm
        model.prepareNewConversation()
        model.prompt = "A different topic"
        XCTAssertTrue(model.startConversation())
        await model.waitForPendingReplies()
        let currentID = model.activeSessionID
        let currentMessages = model.messages
        model.settings.tone = .formal
        model.draft = "Keep my unsent draft"
        await probe.release()
        await finish(model)
        XCTAssertEqual(model.activeSessionID, currentID)
        XCTAssertEqual(model.messages, currentMessages)
        XCTAssertEqual(model.settings.tone, .formal)
        XCTAssertEqual(model.draft, "Keep my unsent draft")
        let archived = try XCTUnwrap(model.history.first { $0.id == oldID })
        XCTAssertEqual(archived.messages.first { $0.id == recordedID }?.transcription?.text, "I like green tea.")
        XCTAssertEqual(archived.messages.last?.replyToMessageID, recordedID)
        XCTAssertEqual(archived.settings.tone, .warm)
        XCTAssertEqual(archived.grammarObservations.count, 1)
    }

    @MainActor
    func testAudioReplacementKeepsOriginalTranscriptAndCountsBothVersions() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let probe = SpeechProbe(texts: ["I like green tea.", "I prefer black tea."])
        let model = await liveModel(probe)
        let sessionID = try XCTUnwrap(model.activeSessionID)
        let originalClip = try makeClip(in: directory)
        XCTAssertTrue(model.commitRecording(originalClip, in: sessionID))
        let originalID = try XCTUnwrap(model.messages.last?.id)
        await finish(model)
        let original = try XCTUnwrap(model.messages.first { $0.id == originalID })
        model.selectMessage(originalID)
        model.perform(.edit, on: originalID)
        // Cancel the injected-denied microphone task, retaining the editor ID.
        model.audio.cancelDraft()
        let replacement = try makeClip(in: directory)
        XCTAssertTrue(model.commitRecording(replacement, in: sessionID, replacing: originalID))
        await finish(model)
        let versions = model.messageVersions.filter { $0.logicalMessageID == original.logicalMessageID }
        XCTAssertEqual(versions.count, 2)
        XCTAssertEqual(versions[0], original)
        XCTAssertEqual(versions[1].replacesMessageID, original.id)
        XCTAssertEqual(versions[1].revision, 2)
        XCTAssertEqual(versions[1].transcription?.text, "I prefer black tea.")
        XCTAssertEqual(versions[1].modality, .spoken)
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalClip.url.path))
        XCTAssertEqual(model.messages.last?.replyToMessageID, versions[1].id)
        let report = try await model.statisticsSnapshot()
        XCTAssertEqual(report.overall.practiceAttempts, 2)
        XCTAssertEqual(report.overall.wordCount, 8)
        XCTAssertEqual(report.overall.grammarEvaluatedAttempts, 2)
    }

    @MainActor
    func testFailedTranscriptionSurvivesRelaunchWithItsPromotedRecording() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dataDirectory = root.appendingPathComponent("Data", isDirectory: true)
        let first = SpeechProbe(failFirst: true)
        let writer = ConversationViewModel.persistent(directory: dataDirectory,
            audioTranscriber: { try await first.transcribe($0) })
        writer.suggestPrompt()
        XCTAssertTrue(writer.startConversation())
        let id = try XCTUnwrap(writer.activeSessionID)
        let clip = try makeClip(in: root)
        XCTAssertTrue(writer.commitRecording(clip, in: id))
        await writer.waitForPendingTranscriptions()
        let recorded = try XCTUnwrap(writer.messages.last)
        let durable = try XCTUnwrap(writer.audioClip(for: recorded))
        XCTAssertNotEqual(durable.url, clip.url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: durable.url.path))
        let second = SpeechProbe()
        let reader = ConversationViewModel.persistent(directory: dataDirectory,
            audioTranscriber: { try await second.transcribe($0) })
        await reader.waitForPendingTranscriptions()
        let noAutomaticCalls = await second.speechURLs
        XCTAssertTrue(noAutomaticCalls.isEmpty)
        XCTAssertTrue(reader.openConversation(id))
        reader.retryReply()
        await reader.waitForPendingTranscriptions()
        await reader.waitForPendingTextAnalyses()
        XCTAssertEqual(reader.messages.last?.id, recorded.id)
        XCTAssertEqual(reader.messages.last?.transcription?.text, "I like green tea.")
        XCTAssertEqual(reader.audioClip(for: reader.messages.last!), durable)
        let calls = await second.speechURLs
        XCTAssertEqual(calls, [durable.url])
        let reloaded = ConversationViewModel.persistent(directory: dataDirectory)
        XCTAssertEqual(reloaded.history.first?.messages.last?.transcription?.text, "I like green tea.")
        XCTAssertNil(reloaded.history.first?.pendingTranscription)
    }

    @MainActor
    func testQueuedWorkResumesButInterruptedWorkRequiresRetry() async throws {
        for attempted in [false, true] {
            let root = try makeDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let id = UUID().uuidString
            let clip = try makeClip(in: root)
            let message = Message(conversationID: id, senderRole: .user, modality: .spoken,
                content: .audio(.init(storageKey: clip.url.lastPathComponent, durationSeconds: clip.duration)))
            var job = SpeechTranscriptionJob(message: message, requestsPartnerReply: false)
            if attempted { job.state = .attempted }
            let session = ConversationSession(id: id, title: "Test", prompt: "Practice", messages: [message], settings: .init(), pendingTranscription: job)
            let store = try ConversationHistoryStore(directory: root.appendingPathComponent("Data"))
            _ = try store.load()
            _ = try store.save(session, recordingSources: [clip.url.lastPathComponent: clip.url])
            let probe = SpeechProbe()
            let model = ConversationViewModel.persistent(store: store, audioTranscriber: { try await probe.transcribe($0) })
            await model.waitForPendingTranscriptions()
            let calls = await probe.speechURLs
            XCTAssertEqual(calls.count, attempted ? 0 : 1)
            if attempted {
                XCTAssertTrue(model.openConversation(id))
                XCTAssertFalse(model.isGeneratingReply)
                model.retryReply()
                await model.waitForPendingTranscriptions()
            }
            await model.waitForPendingTextAnalyses()
            XCTAssertNotNil(model.history.first?.messages.last?.transcription)
        }
    }

    @MainActor
    func testBackgroundCancellationCannotApplyALateTranscriptOrRequestAReply() async throws {
        let started = expectation(description: "Recognition started")
        let probe = SpeechProbe(pauseFirst: true, onFirst: { started.fulfill() })
        defer { Task { await probe.release() } }
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = await liveModel(probe)
        let clip = try makeClip(in: root)
        XCTAssertTrue(model.commitRecording(clip, in: try XCTUnwrap(model.activeSessionID)))
        await fulfillment(of: [started], timeout: 2)
        model.interruptTranscription()
        await probe.release()
        await model.waitForPendingTranscriptions()
        XCTAssertEqual(model.pendingTranscription?.state, .failed)
        XCTAssertNil(model.messages.last?.transcription)
        XCTAssertTrue(FileManager.default.fileExists(atPath: clip.url.path))
        let calls = await probe.replyRequests
        XCTAssertEqual(calls.count, 1)
        model.retryReply()
        await finish(model)
        XCTAssertNil(model.pendingTranscription)
        XCTAssertEqual(model.messages.filter { $0.senderRole == .user }.count, 1)
    }

    @MainActor
    func testInvalidRecognitionRetainsRecordingAndNeverGeneratesRepliesOrGrammar() async throws {
        for value in [Message.Transcription(text: " ", confidence: nil), .init(text: String(repeating: "a", count: 4001), confidence: nil),
                      .init(text: "I like tea.", confidence: .nan)] {
            let root = try makeDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let probe = SpeechProbe(overrideResult: value)
            let model = await liveModel(probe)
            let clip = try makeClip(in: root)
            XCTAssertTrue(model.commitRecording(clip, in: try XCTUnwrap(model.activeSessionID)))
            await model.waitForPendingTranscriptions()
            XCTAssertEqual(model.pendingTranscription?.state, .failed)
            XCTAssertNil(model.messages.last?.transcription)
            XCTAssertTrue(model.grammarObservations.isEmpty)
            XCTAssertTrue(FileManager.default.fileExists(atPath: clip.url.path))
            let replies = await probe.replyRequests
            XCTAssertEqual(replies.count, 1)
            model.dismissFailedReply()
            XCTAssertTrue(model.canSubmitMessage)
            XCTAssertNotNil(model.messages.last?.audioAttachment)
        }
    }

    @MainActor
    func testFailedRecordingSaveDoesNotStartTranscription() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dataDirectory = root.appendingPathComponent("Data")
        let writer = ConversationViewModel.persistent(directory: dataDirectory)
        writer.suggestPrompt()
        XCTAssertTrue(writer.startConversation())
        let id = try XCTUnwrap(writer.activeSessionID)
        let probe = SpeechProbe()
        let reader = ConversationViewModel.persistent(store: try ConversationHistoryStore(directory: dataDirectory, allowsSave: false),
                                                       audioTranscriber: { try await probe.transcribe($0) })
        XCTAssertTrue(reader.openConversation(id))
        let clip = try makeClip(in: root)
        XCTAssertFalse(reader.commitRecording(clip, in: id))
        await reader.waitForPendingTranscriptions()
        XCTAssertNil(reader.pendingTranscription)
        XCTAssertEqual(reader.messages, writer.messages)
        XCTAssertTrue(FileManager.default.fileExists(atPath: clip.url.path))
        let calls = await probe.speechURLs
        XCTAssertTrue(calls.isEmpty)
    }

    @MainActor
    func testOldRecordingsWithoutJobsAreNotTranscribedOnLaunch() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = ConversationViewModel(history: [])
        model.suggestPrompt()
        XCTAssertTrue(model.startConversation())
        XCTAssertTrue(model.commitRecording(try makeClip(in: root), in: try XCTUnwrap(model.activeSessionID)))
        let probe = SpeechProbe()
        let reader = ConversationViewModel(history: model.history, audioTranscriber: { try await probe.transcribe($0) })
        await reader.waitForPendingTranscriptions()
        let calls = await probe.speechURLs
        XCTAssertTrue(calls.isEmpty)
        XCTAssertNil(reader.history.first?.messages.last?.transcription)
    }

    @MainActor
    private func liveModel(_ probe: SpeechProbe) async -> ConversationViewModel {
        let model = ConversationViewModel(history: [], audio: ConversationAudioController(permissionRequest: { false }),
            replyGenerator: { await probe.reply($0) }, grammarEvaluator: { await probe.grammar($0) },
            audioTranscriber: { try await probe.transcribe($0) })
        model.prompt = "Practice English"
        XCTAssertTrue(model.startConversation())
        await model.waitForPendingReplies()
        return model
    }

    @MainActor
    private func finish(_ model: ConversationViewModel) async {
        await model.waitForPendingTranscriptions()
        await model.waitForPendingReplies()
        await model.waitForPendingGrammarEvaluations()
        await model.waitForPendingTextAnalyses()
    }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeClip(in directory: URL) throws -> LocalAudioClip {
        let url = directory.appendingPathComponent(UUID().uuidString + ".caf")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4410))
        buffer.frameLength = 4410
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0..<4410 { samples[index] = 0 }
        do { let writer = try AVAudioFile(forWriting: url, settings: format.settings); try writer.write(from: buffer) }
        return LocalAudioClip(url: url, duration: 0.1)
    }
}

private actor SpeechProbe {
    private let texts: [String]
    private let failFirst: Bool
    private let pauseFirst: Bool
    private let overrideResult: Message.Transcription?
    private let onFirst: @Sendable () -> Void
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var speechURLs: [URL] = []
    private(set) var replyRequests: [ConversationReplyRequest] = []

    init(texts: [String] = ["I like green tea."], failFirst: Bool = false, pauseFirst: Bool = false,
         overrideResult: Message.Transcription? = nil, onFirst: @escaping @Sendable () -> Void = {}) {
        self.texts = texts
        self.failFirst = failFirst
        self.pauseFirst = pauseFirst
        self.overrideResult = overrideResult
        self.onFirst = onFirst
    }

    func transcribe(_ clip: LocalAudioClip) async throws -> Message.Transcription {
        speechURLs.append(clip.url)
        let index = speechURLs.count - 1
        if index == 0 {
            onFirst()
            if pauseFirst && !released { await withCheckedContinuation { continuation = $0 } }
            if failFirst { throw SpeechTranscriptionError.modelUnavailable }
        }
        return overrideResult ?? .init(text: texts[min(index, texts.count - 1)], confidence: nil)
    }

    func reply(_ request: ConversationReplyRequest) -> ConversationReplyResponse {
        replyRequests.append(request)
        return .init(requestID: request.requestID, conversationID: request.conversationID, replyToMessageID: request.replyToMessageID,
            kind: request.kind, text: "What tea do you like?", settings: request.settings, model: "test", promptVersion: "test")
    }

    func grammar(_ request: GrammarEvaluationRequest) -> GrammarEvaluationResponse {
        .init(requestID: request.requestID, conversationID: request.conversationID, messageID: request.messageID,
            messageRevision: request.messageRevision, textSource: request.textSource, rubricVersion: "grammar-v1",
            taxonomyVersion: "grammar-five-v1", model: "test", evaluatedAtSeconds: Date().timeIntervalSince1970, opportunities: [])
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}
