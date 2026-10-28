import AVFoundation
import XCTest
@testable import XiaoLiao

final class ConversationAudioTests: XCTestCase {
    @MainActor
    func testMicrophoneDenialReturnsToIdleAndOffersSettings() async {
        let audio = ConversationAudioController(permissionRequest: { false })
        let request = audio.startRecording()
        XCTAssertEqual(audio.recordingState, .requestingPermission)
        XCTAssertFalse(audio.canSend)
        await request?.value
        XCTAssertEqual(audio.recordingState, .idle)
        XCTAssertTrue(audio.issue?.offersSettings == true)
        XCTAssertNil(audio.reviewClip)
        XCTAssertFalse(audio.isPlaying)
    }

    @MainActor
    func testLeavingDuringPermissionRequestCannotStartRecordingLater() async {
        let requested = expectation(description: "Permission requested")
        var reply: CheckedContinuation<Bool, Never>?
        let audio = ConversationAudioController(permissionRequest: {
            await withCheckedContinuation { continuation in
                reply = continuation
                requested.fulfill()
            }
        })
        let request = audio.startRecording()
        await fulfillment(of: [requested], timeout: 2)
        audio.cancelDraft()
        reply?.resume(returning: true)
        await request?.value
        XCTAssertEqual(audio.recordingState, .idle)
        XCTAssertFalse(audio.hasDraft)
        XCTAssertNil(audio.issue)
    }

    @MainActor
    func testInterruptionCancelsPendingMicrophoneRequestWithoutResuming() async {
        let requested = expectation(description: "Permission requested")
        var reply: CheckedContinuation<Bool, Never>?
        let audio = ConversationAudioController(permissionRequest: {
            await withCheckedContinuation { continuation in
                reply = continuation
                requested.fulfill()
            }
        })
        let request = audio.startRecording()
        await fulfillment(of: [requested], timeout: 2)
        audio.interrupt()
        reply?.resume(returning: true)
        await request?.value
        XCTAssertEqual(audio.recordingState, .idle)
        XCTAssertNotNil(audio.issue)
        XCTAssertFalse(audio.issue?.offersSettings ?? true)
    }

    @MainActor
    func testPausedSegmentsJoinInOrderWithoutDroppingEarlierSpeech() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try makeClip(in: directory, value: 0.25)
        let second = try makeClip(in: directory, value: -0.5)
        let output = directory.appendingPathComponent("joined.caf")
        let duration = try ConversationAudioController.joinSegments([first.url, second.url], to: output)
        XCTAssertEqual(duration, 0.2, accuracy: 0.001)
        let joined = try AVAudioFile(forReading: output)
        XCTAssertEqual(joined.length, 8_820)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: joined.processingFormat, frameCapacity: 8_820))
        try joined.read(into: buffer)
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        XCTAssertEqual(samples[0], 0.25, accuracy: 0.0001)
        XCTAssertEqual(samples[4_409], 0.25, accuracy: 0.0001)
        XCTAssertEqual(samples[4_410], -0.5, accuracy: 0.0001)
        XCTAssertEqual(samples[8_819], -0.5, accuracy: 0.0001)
    }

    @MainActor
    func testEmptyAudioCannotBecomeASentMessage() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertThrowsError(try ConversationAudioController.joinSegments([], to: directory.appendingPathComponent("empty.caf")))
        let model = makeConversation()
        let id = try XCTUnwrap(model.activeSessionID)
        let missing = LocalAudioClip(url: directory.appendingPathComponent("missing.caf"), duration: 1)
        XCTAssertFalse(model.commitRecording(missing, in: id))
        let clip = try makeClip(in: directory)
        XCTAssertFalse(model.commitRecording(LocalAudioClip(url: clip.url, duration: 0), in: id))
        XCTAssertFalse(model.commitRecording(LocalAudioClip(url: clip.url, duration: .nan), in: id))
        XCTAssertEqual(model.messages, MockConversation.messages)
    }

    @MainActor
    func testRecordedMessageRetainsAudioAndVoiceAppearanceAcrossHistory() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = makeConversation()
        let sessionID = try XCTUnwrap(model.activeSessionID)
        let clip = try makeClip(in: directory)
        XCTAssertTrue(model.commitRecording(clip, in: sessionID))
        let sent = try XCTUnwrap(model.messages.last)
        XCTAssertEqual(sent.sender, .learner)
        XCTAssertEqual(sent.communicationMethod, .voice)
        XCTAssertEqual(sent.localAudio, clip)
        XCTAssertEqual(sent.content, .text("语音消息 · 1秒"))
        XCTAssertNil(sent.mockTranslation)
        XCTAssertTrue(model.isAvailable(.play, for: sent))
        XCTAssertFalse(model.isAvailable(.translate, for: sent))
        model.showTextInput()
        model.draft = "A typed reply"
        XCTAssertTrue(model.submitDraft())
        XCTAssertFalse(model.actions(for: sent).contains(.edit))
        model.prepareNewConversation()
        XCTAssertTrue(FileManager.default.fileExists(atPath: clip.url.path))
        XCTAssertTrue(model.openConversation(sessionID))
        XCTAssertEqual(model.messages[2], sent)
        XCTAssertEqual(model.messages.last?.communicationMethod, .text)
    }

    @MainActor
    func testFinalizedClipCannotBeCommittedIntoAnotherConversation() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = makeConversation()
        let originalID = try XCTUnwrap(model.activeSessionID)
        let clip = try makeClip(in: directory)
        model.prepareNewConversation()
        model.suggestPrompt()
        XCTAssertTrue(model.startConversation())
        XCTAssertFalse(model.commitRecording(clip, in: originalID))
        XCTAssertEqual(model.messages, MockConversation.messages)
        XCTAssertEqual(model.history.first(where: { $0.id == originalID })?.messages, MockConversation.messages)
    }

    @MainActor
    func testAudioReplacementIsAtomicAndCancelKeepsOriginal() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = makeConversation()
        let sessionID = try XCTUnwrap(model.activeSessionID)
        let original = try makeClip(in: directory)
        XCTAssertTrue(model.commitRecording(original, in: sessionID))
        let message = try XCTUnwrap(model.messages.last)
        model.selectMessage(message.id)
        model.perform(.edit, on: message.id)
        model.cancelAudioDraft()
        XCTAssertEqual(model.messages.last, message)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.url.path))

        let replacement = try makeClip(in: directory, value: 0.5)
        XCTAssertFalse(model.commitRecording(replacement, in: sessionID, replacing: message.id))
        model.deselectMessage()
        model.selectMessage(message.id)
        model.perform(.edit, on: message.id)
        // Stop the injected permission task; commit represents a finalized replacement.
        model.audio.cancelDraft()
        XCTAssertTrue(model.commitRecording(replacement, in: sessionID, replacing: message.id))
        XCTAssertEqual(model.messages.count, 3)
        XCTAssertEqual(model.messages.last?.id, message.id)
        XCTAssertEqual(model.messages.last?.communicationMethod, .voice)
        XCTAssertEqual(model.messages.last?.localAudio, replacement)
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.url.path))
        XCTAssertEqual(model.history.first?.messages.last?.localAudio, replacement)
    }

    @MainActor
    func testOlderRecordingCannotBeReplacedAfterAnotherLearnerMessage() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = makeConversation()
        let sessionID = try XCTUnwrap(model.activeSessionID)
        let original = try makeClip(in: directory)
        XCTAssertTrue(model.commitRecording(original, in: sessionID))
        let message = try XCTUnwrap(model.messages.last)
        model.selectMessage(message.id)
        model.perform(.edit, on: message.id)
        model.audio.cancelDraft()
        let later = ConversationMessage(id: "later", sender: .learner, communicationMethod: .text, content: .text("Later"))
        let session = ConversationSession(id: "later-session", title: "Later", prompt: "Later", messages: model.messages + [later], settings: .init())
        // A restored session with a newer reply must enforce the same policy.
        let restored = ConversationViewModel(history: [session])
        XCTAssertTrue(restored.openConversation(session.id))
        XCTAssertFalse(restored.actions(for: message).contains(.edit))
        let replacement = try makeClip(in: directory)
        XCTAssertFalse(restored.commitRecording(replacement, in: session.id, replacing: message.id))
        XCTAssertEqual(restored.messages[2].localAudio, original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.url.path))
    }

    @MainActor
    private func makeConversation() -> ConversationViewModel {
        let model = ConversationViewModel(audio: ConversationAudioController(permissionRequest: { false }))
        model.suggestPrompt()
        XCTAssertTrue(model.startConversation())
        return model
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("XiaoLiaoAudioTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @MainActor
    private func makeClip(in directory: URL, value: Float = 0.25) throws -> LocalAudioClip {
        let url = directory.appendingPathComponent(UUID().uuidString + ".caf")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_410))
        buffer.frameLength = 4_410
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0..<4_410 { samples[index] = value }
        // The writer closes before the caller reads or joins the file.
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        return LocalAudioClip(url: url, duration: 0.1)
    }
}
