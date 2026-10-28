import XCTest
import UIKit
@testable import XiaoLiao

final class ConversationViewModelTests: XCTestCase {
    @MainActor
    func testRequiredPromptAndCanonicalFixtureMetadata() throws {
        let model = ConversationViewModel(history: [])
        model.prompt = " \n\t "
        XCTAssertFalse(model.startConversation())
        model.suggestPrompt()
        XCTAssertTrue(model.startConversation())
        let sessionID = try XCTUnwrap(model.activeSessionID)
        XCTAssertEqual(model.messages.count, 2)
        XCTAssertEqual(Set(model.messages.map(\.id)).count, 2)
        XCTAssertTrue(model.messages.allSatisfy { $0.conversationID == sessionID && $0.revision == 1 && !$0.isEdit && $0.status == .complete })
        XCTAssertEqual(model.messages[1].replyToMessageID, model.messages[0].id)
        XCTAssertTrue(model.grammarObservations.isEmpty)
        XCTAssertTrue(model.vocabularyObservations.isEmpty)
    }

    @MainActor
    func testSelectionDetailsAndUnavailableFixturePlayback() {
        let model = makeConversation()
        let partner = model.messages[0]
        let learner = model.messages[1]
        model.perform(.transcribe, on: partner.id)
        XCTAssertNil(model.detailText(for: partner))
        model.selectMessage(partner.id)
        model.perform(.transcribe, on: partner.id)
        XCTAssertEqual(model.detailText(for: partner), "Do you love turtles?")
        model.perform(.translate, on: partner.id)
        XCTAssertEqual(model.detailText(for: partner), "我今天喝了杯咖啡")
        model.selectMessage(learner.id)
        XCTAssertEqual(model.selectedMessageID, learner.id)
        model.selectMessage(learner.id)
        XCTAssertNil(model.selectedMessageID)
        XCTAssertFalse(model.isAvailable(.play, for: partner))
        XCTAssertFalse(model.isAvailable(.repeatAudio, for: partner))
    }

    @MainActor
    func testEditsAppendImmutableVersionsAndStayInOriginalFeedPosition() throws {
        let model = makeConversation()
        let original = model.messages[1]
        model.selectMessage(original.id)
        model.perform(.edit, on: original.id)
        XCTAssertEqual(model.draft, "Yes, I also love turtles!")
        model.draft = " \n "
        XCTAssertFalse(model.submitDraft())
        XCTAssertEqual(model.messageVersions.count, 2)
        model.draft = "  I love sea turtles.  "
        XCTAssertTrue(model.submitDraft())
        let edited = model.messages[1]
        XCTAssertEqual(model.messages.count, 2)
        XCTAssertEqual(model.messageVersions.count, 3)
        XCTAssertEqual(model.messageVersions[1], original)
        XCTAssertNotEqual(edited.id, original.id)
        XCTAssertEqual(edited.logicalMessageID, original.id)
        XCTAssertEqual(edited.replacesMessageID, original.id)
        XCTAssertEqual(edited.revision, 2)
        XCTAssertTrue(edited.isEdit)
        XCTAssertEqual(edited.modality, .spoken)
        XCTAssertEqual(edited.replyToMessageID, original.replyToMessageID)
        XCTAssertEqual(edited.content, .text("I love sea turtles."))
        XCTAssertEqual(edited.transcription?.text, "I love sea turtles.")
        XCTAssertNil(edited.transcription?.confidence)
        XCTAssertNil(model.translation(for: edited))
        model.selectMessage(edited.id)
        model.perform(.edit, on: edited.id)
        model.draft = "I really love turtles."
        XCTAssertTrue(model.submitDraft())
        XCTAssertEqual(model.messages[1].replacesMessageID, edited.id)
        XCTAssertEqual(model.messages[1].revision, 3)
        XCTAssertEqual(model.messageVersions[2], edited)
        XCTAssertFalse(model.isAvailable(.edit, for: original))
        let sessionID = try XCTUnwrap(model.activeSessionID)
        let versions = model.messageVersions
        model.prepareNewConversation()
        XCTAssertTrue(model.openConversation(sessionID))
        XCTAssertEqual(model.messageVersions, versions)
        XCTAssertEqual(model.messages.count, 2)
    }

    @MainActor
    func testTypedSendsPreserveColorsAndLatestLearnerEditPolicy() throws {
        let model = makeConversation()
        let older = model.messages[1]
        model.draft = "A typed reply"
        XCTAssertTrue(model.submitDraft())
        let newest = try XCTUnwrap(model.messages.last)
        XCTAssertEqual(newest.senderRole, .user)
        XCTAssertEqual(newest.modality, .written)
        XCTAssertEqual(newest.replyToMessageID, model.messages[0].id)
        model.showVoiceInput()
        XCTAssertEqual(model.messages[1].modality, .spoken)
        XCTAssertEqual(model.messages.last?.modality, .written)
        XCTAssertFalse(model.actions(for: older).contains(.edit))
        model.selectMessage(older.id)
        model.perform(.edit, on: older.id)
        XCTAssertNil(model.editingMessageID)
        model.selectMessage(newest.id)
        model.perform(.edit, on: newest.id)
        model.draft = "Edited typed reply"
        XCTAssertTrue(model.submitDraft())
        XCTAssertEqual(model.messages.last?.modality, .written)
        XCTAssertEqual(model.messages.last?.logicalMessageID, newest.id)
    }

    @MainActor
    func testPartnerReplyKeepsLatestLearnerEditableAndReplyPointsAtOriginalVersion() {
        let learner = Message(id: "learner", conversationID: "session", senderRole: .user, modality: .written, content: .text("I love turtles."))
        let partner = Message(id: "partner", conversationID: "session", senderRole: .aiPartner, modality: .written,
                              content: .text("What do you like about them?"), replyToMessageID: learner.id)
        let session = ConversationSession(id: "session", title: "乌龟", prompt: "Turtles", messages: [learner, partner], settings: .init())
        let model = ConversationViewModel(history: [session])
        XCTAssertTrue(model.openConversation(session.id))
        XCTAssertFalse(model.isAvailable(.edit, for: partner))
        model.selectMessage(learner.id)
        model.perform(.edit, on: learner.id)
        model.draft = "I really love turtles."
        XCTAssertTrue(model.submitDraft())
        XCTAssertEqual(model.messages[0].content, .text("I really love turtles."))
        XCTAssertEqual(model.messages[1], partner)
        XCTAssertEqual(model.messages[1].replyToMessageID, learner.id)
        XCTAssertEqual(model.messageVersions[0], learner)
    }

    @MainActor
    func testSystemModeTextOnlyAndReplyLinkPersistedWithoutPartnerGeneration() {
        let model = makeConversation()
        model.toggleSystemMessageMode()
        model.showVoiceInput()
        model.beginRecording()
        XCTAssertEqual(model.inputMode, .text)
        XCTAssertEqual(model.audio.recordingState, .idle)
        model.draft = " \n "
        XCTAssertFalse(model.submitDraft())
        XCTAssertTrue(model.isSystemMessageMode)
        model.draft = MockConversation.systemRequest
        XCTAssertTrue(model.submitDraft())
        XCTAssertEqual(model.messages.count, 4)
        let request = model.messages[2]
        let reply = model.messages[3]
        XCTAssertEqual(request.senderRole, .user)
        XCTAssertEqual(request.purpose, .systemAssistance)
        XCTAssertEqual(reply.senderRole, .system)
        XCTAssertEqual(reply.purpose, .systemAssistance)
        XCTAssertEqual(reply.replyToMessageID, request.id)
        XCTAssertEqual(reply.modality, .written)
        XCTAssertEqual(reply.content, .text(MockConversation.systemReply))
        XCTAssertNil(reply.audioAttachment)
        XCTAssertTrue(request.actions.isEmpty)
        XCTAssertTrue(reply.actions.isEmpty)
        XCTAssertFalse(model.isAvailable(.edit, for: model.messages[1]))
        XCTAssertEqual(model.settings.vocabulary, .simple)
        XCTAssertFalse(model.isSystemMessageMode)
        XCTAssertEqual(model.inputMode, .voice)
        model.draft = "Back to practice"
        XCTAssertTrue(model.submitDraft())
        XCTAssertEqual(model.messages.last?.purpose, .conversationPractice)
        XCTAssertEqual(model.messages.last?.replyToMessageID, model.messages[0].id)
    }

    @MainActor
    func testSystemQuestionsCancellationAndNavigationClearTransientMode() {
        let model = makeConversation()
        model.showTextInput()
        model.toggleSystemMessageMode()
        model.toggleSystemMessageMode()
        XCTAssertEqual(model.inputMode, .text)
        model.settings.tone = .formal
        model.toggleSystemMessageMode()
        model.draft = MockConversation.systemSettingsQuestion
        XCTAssertTrue(model.submitDraft())
        guard case let .text(answer) = model.messages.last!.content else { return XCTFail("Missing text reply") }
        XCTAssertTrue(answer.contains("正式"))
        let settings = model.settings
        model.toggleSystemMessageMode()
        model.draft = "Arbitrary question"
        XCTAssertTrue(model.submitDraft())
        XCTAssertEqual(model.settings, settings)
        model.toggleSystemMessageMode()
        model.draft = "Unsent"
        let saved = model.history
        model.leaveFeed()
        XCTAssertFalse(model.isSystemMessageMode)
        XCTAssertTrue(model.draft.isEmpty)
        XCTAssertEqual(model.history, saved)
    }

    @MainActor
    func testRestartingConversationCreatesDistinctMessageIdentitiesAndClearsPresentation() {
        let model = makeConversation()
        let originalIDs = Set(model.messages.map(\.id))
        model.selectMessage(model.messages[0].id)
        model.perform(.transcribe, on: model.messages[0].id)
        model.draft = "Another message"
        XCTAssertTrue(model.submitDraft())
        XCTAssertTrue(model.startConversation())
        XCTAssertEqual(model.messages.count, 2)
        XCTAssertTrue(originalIDs.isDisjoint(with: Set(model.messages.map(\.id))))
        XCTAssertNil(model.selectedMessageID)
        XCTAssertTrue(model.details.isEmpty)
        XCTAssertTrue(model.draft.isEmpty)
    }

    @MainActor
    func testBundledArtworkLoadsWithCorrectProportions() throws {
        for artwork in FigmaArtwork.allCases {
            let image = try XCTUnwrap(UIImage(named: artwork.rawValue))
            XCTAssertGreaterThan(image.size.width, 0)
            XCTAssertGreaterThan(image.size.height, 0)
            XCTAssertEqual(image.size.width / image.size.height, artwork.size.width / artwork.size.height,
                           accuracy: max(0.01, 1 / min(artwork.size.width, artwork.size.height)))
        }
    }

    @MainActor
    private func makeConversation() -> ConversationViewModel {
        let model = ConversationViewModel()
        model.suggestPrompt()
        XCTAssertTrue(model.startConversation())
        return model
    }
}
