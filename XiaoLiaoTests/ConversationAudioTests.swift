import AVFoundation
import XCTest
@testable import XiaoLiao

final class ConversationAudioTests: XCTestCase {
    @MainActor
    func testPartnerSpeechAvailabilitySurvivesHistoryAndKeepsSystemAndLearnerTextSilent() throws {
        let id = "speech-session"
        let partner = Message(conversationID: id, senderRole: .aiPartner, modality: .written,
                              content: .text("What do you like about tea?"), origin: .fixture)
        let learner = Message(conversationID: id, senderRole: .user, modality: .written,
                              content: .text("I like green tea."), origin: .fixture)
        let system = Message(conversationID: id, senderRole: .system, purpose: .systemAssistance,
                             modality: .written, content: .text("已调整对话设置。"), origin: .fixture)
        let unfinished = Message(conversationID: id, senderRole: .aiPartner, modality: .written,
                                 content: .text("An unfinished reply"), status: .failed, origin: .fixture)
        let session = ConversationSession(id: id, title: "Tea", prompt: "Talk about tea",
                                          messages: [partner, learner, system, unfinished], settings: .init())
        // Old text replies need no audio-file migration, transcription or paid work.
        let restored = try JSONDecoder().decode(ConversationSession.self, from: JSONEncoder().encode(session))
        let model = ConversationViewModel(history: [restored])
        XCTAssertTrue(model.openConversation(id))
        XCTAssertTrue(model.isAvailable(.play, for: partner))
        for message in [learner, system, unfinished] {
            XCTAssertFalse(model.isAvailable(.play, for: message))
            model.selectMessage(message.id)
            model.perform(.play, on: message.id)
            XCTAssertNil(model.audio.playbackID)
        }
        XCTAssertEqual(model.messageVersions, session.messages)
        XCTAssertNil(model.audioClip(for: partner))
        model.prepareNewConversation()
        XCTAssertFalse(model.isAvailable(.play, for: partner))
        XCTAssertTrue(model.openConversation(id))
        XCTAssertTrue(model.isAvailable(.play, for: partner))
        XCTAssertEqual(model.messageVersions, session.messages)
        XCTAssertFalse(model.audio.isPlaying)
    }

    @MainActor
    func testMicrophoneRequestBlocksPartnerSpeechAndDenialRestoresPlaybackAction() async {
        let id = "speech-recording-session"
        let partner = Message(conversationID: id, senderRole: .aiPartner, modality: .written,
                              content: .text("Tell me about your day."), origin: .fixture)
        let session = ConversationSession(id: id, title: "Today", prompt: "Talk about today",
                                          messages: [partner], settings: .init())
        let audio = ConversationAudioController(permissionRequest: { false })
        let model = ConversationViewModel(history: [session], audio: audio)
        XCTAssertTrue(model.openConversation(id))
        model.selectMessage(partner.id)
        XCTAssertTrue(model.isAvailable(.play, for: partner))
        let request = audio.startRecording()
        XCTAssertEqual(audio.recordingState, .requestingPermission)
        XCTAssertFalse(model.isAvailable(.play, for: partner))
        model.perform(.play, on: partner.id)
        XCTAssertFalse(audio.isPlaying)
        XCTAssertNil(audio.playbackID)
        await request?.value
        XCTAssertTrue(model.isAvailable(.play, for: partner))
        XCTAssertEqual(model.messageVersions, [partner])
    }

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
    func testInvalidAndStaleRecordingCannotBeCommitted() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = makeConversation()
        let id = try XCTUnwrap(model.activeSessionID)
        let original = model.messageVersions
        let missing = LocalAudioClip(url: directory.appendingPathComponent("missing.caf"), duration: 1)
        XCTAssertFalse(model.commitRecording(missing, in: id))
        let clip = try makeClip(in: directory)
        XCTAssertFalse(model.commitRecording(LocalAudioClip(url: clip.url, duration: 0), in: id))
        XCTAssertFalse(model.commitRecording(LocalAudioClip(url: clip.url, duration: .nan), in: id))
        model.prepareNewConversation()
        model.suggestPrompt()
        XCTAssertTrue(model.startConversation())
        XCTAssertFalse(model.commitRecording(clip, in: id))
        XCTAssertEqual(model.messages.count, 2)
        XCTAssertEqual(model.history.first(where: { $0.id == id })?.messages, original)
    }

    @MainActor
    func testRecordingMetadataAndPlaybackReferenceSurviveHistorySwitches() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = makeConversation()
        let id = try XCTUnwrap(model.activeSessionID)
        let clip = try makeClip(in: directory)
        XCTAssertTrue(model.commitRecording(clip, in: id))
        let sent = try XCTUnwrap(model.messages.last)
        XCTAssertEqual(sent.senderRole, .user)
        XCTAssertEqual(sent.modality, .spoken)
        XCTAssertEqual(sent.audioAttachment?.durationSeconds, clip.duration)
        XCTAssertEqual(sent.audioAttachment?.storageKey, clip.url.lastPathComponent)
        XCTAssertNil(sent.transcription)
        XCTAssertEqual(model.audioClip(for: sent), clip)
        XCTAssertTrue(model.isAvailable(.play, for: sent))
        XCTAssertFalse(model.isAvailable(.translate, for: sent))
        model.showTextInput()
        model.draft = "A typed reply"
        XCTAssertTrue(model.submitDraft())
        XCTAssertFalse(model.actions(for: sent).contains(.edit))
        model.prepareNewConversation()
        XCTAssertTrue(model.openConversation(id))
        XCTAssertEqual(model.messages[2], sent)
        XCTAssertEqual(model.audioClip(for: sent), clip)
        XCTAssertEqual(model.messages.last?.modality, .written)
    }

    @MainActor
    func testAudioEditKeepsOriginalFileAndAppendsReplacementVersion() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = makeConversation()
        let id = try XCTUnwrap(model.activeSessionID)
        let originalClip = try makeClip(in: directory)
        XCTAssertTrue(model.commitRecording(originalClip, in: id))
        let original = try XCTUnwrap(model.messages.last)
        model.selectMessage(original.id)
        model.perform(.edit, on: original.id)
        model.cancelAudioDraft()
        XCTAssertEqual(model.messages.last, original)
        let replacement = try makeClip(in: directory, value: 0.5)
        XCTAssertFalse(model.commitRecording(replacement, in: id, replacing: original.id))
        model.deselectMessage()
        model.selectMessage(original.id)
        model.perform(.edit, on: original.id)
        model.audio.cancelDraft()
        XCTAssertTrue(model.commitRecording(replacement, in: id, replacing: original.id))
        let edited = try XCTUnwrap(model.messages.last)
        XCTAssertEqual(model.messages.count, 3)
        XCTAssertEqual(model.messageVersions.count, 4)
        XCTAssertNotEqual(edited.id, original.id)
        XCTAssertEqual(edited.logicalMessageID, original.id)
        XCTAssertEqual(edited.replacesMessageID, original.id)
        XCTAssertEqual(edited.modality, .spoken)
        XCTAssertEqual(model.audioClip(for: edited), replacement)
        XCTAssertEqual(model.audioClip(for: original), originalClip)
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalClip.url.path))
        XCTAssertEqual(model.messageVersions[2], original)
        XCTAssertFalse(model.isAvailable(.edit, for: original))
        model.draft = "Later typed reply"
        XCTAssertTrue(model.submitDraft())
        XCTAssertFalse(model.commitRecording(replacement, in: id, replacing: edited.id))
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
