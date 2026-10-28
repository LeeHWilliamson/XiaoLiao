import XCTest
import UIKit
@testable import XiaoLiao

final class ConversationViewModelTests: XCTestCase {
    @MainActor
    func testBlankTopicsCannotStartAndSuggestionEnablesStart() {
        let model = ConversationViewModel()
        model.prompt = " \n\t "
        XCTAssertFalse(model.startConversation())
        XCTAssertTrue(model.messages.isEmpty)
        model.suggestPrompt()
        XCTAssertTrue(model.startConversation())
        XCTAssertEqual(model.messages, MockConversation.messages)
        XCTAssertNil(model.selectedMessageID)
    }

    @MainActor
    func testSelectionIsExclusiveAndCanBeDismissed() {
        let model = makeConversation()
        let audio = model.messages[0].id
        let text = model.messages[1].id
        model.selectMessage(audio)
        model.selectMessage(text)
        XCTAssertEqual(model.selectedMessageID, text)
        model.selectMessage(text)
        XCTAssertNil(model.selectedMessageID)
        model.selectMessage("unknown")
        XCTAssertNil(model.selectedMessageID)
        model.selectMessage(audio)
        model.deselectMessage()
        XCTAssertNil(model.selectedMessageID)
    }

    @MainActor
    func testOnlySelectedMessageCanToggleAvailableDetails() {
        let model = makeConversation()
        let audio = model.messages[0]
        model.perform(.transcribe, on: audio.id)
        XCTAssertNil(model.detailText(for: audio))
        model.selectMessage(audio.id)
        model.perform(.transcribe, on: audio.id)
        XCTAssertEqual(model.detailText(for: audio), "Do you love turtles?")
        model.perform(.translate, on: audio.id)
        XCTAssertEqual(model.details[audio.id], .translation)
        XCTAssertEqual(model.detailText(for: audio), audio.mockTranslation)
        model.perform(.translate, on: audio.id)
        XCTAssertNil(model.detailText(for: audio))
        XCTAssertFalse(model.isAvailable(.play, for: audio))
        XCTAssertFalse(model.isAvailable(.repeatAudio, for: audio))
    }

    @MainActor
    func testEditingUpdatesSameMessageAndClearsStaleTranslation() {
        let model = makeConversation()
        let original = model.messages[1]
        model.selectMessage(original.id)
        model.perform(.translate, on: original.id)
        model.perform(.edit, on: original.id)
        XCTAssertEqual(model.inputMode, .text)
        XCTAssertEqual(model.draft, "Yes, I also love turtles!")
        model.draft = " \n "
        XCTAssertFalse(model.submitDraft())
        XCTAssertEqual(model.messages[1], original)
        model.draft = "  I love sea turtles.  "
        XCTAssertTrue(model.submitDraft())
        XCTAssertEqual(model.messages.count, 2)
        XCTAssertEqual(model.messages[1].id, original.id)
        XCTAssertEqual(model.messages[1].content, .text("I love sea turtles."))
        XCTAssertEqual(model.messages[1].communicationMethod, .voice)
        XCTAssertNil(model.messages[1].mockTranslation)
        XCTAssertNil(model.details[original.id])
        XCTAssertNil(model.editingMessageID)
    }

    @MainActor
    func testSubmittingDraftAddsOnlyLocalLearnerMessage() {
        let model = makeConversation()
        model.draft = "Hello!"
        XCTAssertTrue(model.submitDraft())
        XCTAssertEqual(model.messages.count, 3)
        XCTAssertEqual(model.messages.last?.content, .text("Hello!"))
        XCTAssertNil(model.messages.last?.mockTranslation)
        XCTAssertEqual(model.draft, "")
    }

    @MainActor
    func testStartingAgainRetainsTopicAndResetsSession() {
        let model = makeConversation()
        let topic = model.prompt
        model.selectMessage(model.messages[0].id)
        model.perform(.transcribe, on: model.messages[0].id)
        model.draft = "Another message"
        model.submitDraft()
        model.inputMode = .text
        XCTAssertTrue(model.startConversation())
        XCTAssertEqual(model.prompt, topic)
        XCTAssertEqual(model.messages, MockConversation.messages)
        XCTAssertNil(model.selectedMessageID)
        XCTAssertTrue(model.details.isEmpty)
        XCTAssertEqual(model.inputMode, .voice)
        XCTAssertTrue(model.draft.isEmpty)
    }

    @MainActor
    func testBundledArtworkLoadsWithCorrectProportions() throws {
        for artwork in FigmaArtwork.allCases {
            let image = try XCTUnwrap(UIImage(named: artwork.rawValue), "Missing artwork: \(artwork.rawValue)")
            XCTAssertGreaterThan(image.size.width, 0)
            XCTAssertGreaterThan(image.size.height, 0)
            XCTAssertEqual(
                image.size.width / image.size.height,
                artwork.size.width / artwork.size.height,
                // UIImage may round a fractional PDF viewport to whole points.
                accuracy: max(0.01, 1 / min(artwork.size.width, artwork.size.height)),
                "Incorrect proportions: \(artwork.rawValue)"
            )
        }
    }

    @MainActor
    func testSendMethodsSurviveInputModeChangesAndHistoryRestore() throws {
        let model = makeConversation()
        let sessionID = try XCTUnwrap(model.activeSessionID)
        XCTAssertEqual(model.messages[1].communicationMethod, .voice)

        model.inputMode = .text
        model.draft = "I typed this message."
        XCTAssertTrue(model.submitDraft())
        let typed = try XCTUnwrap(model.messages.last)
        XCTAssertEqual(typed.sender, .learner)
        XCTAssertEqual(typed.communicationMethod, .text)

        model.showVoiceInput()
        XCTAssertEqual(model.messages[1].communicationMethod, .voice)
        XCTAssertEqual(model.messages.last?.communicationMethod, .text)
        let savedMessages = model.messages
        model.prepareNewConversation()
        XCTAssertTrue(model.openConversation(sessionID))
        XCTAssertEqual(model.messages, savedMessages)
        XCTAssertEqual(model.messages.last?.communicationMethod, .text)
    }

    @MainActor
    func testOnlyLatestLearnerMessageOffersAndAcceptsEdit() throws {
        let model = makeConversation()
        let earlier = model.messages[1]
        model.draft = "My newest message."
        XCTAssertTrue(model.submitDraft())
        let latest = try XCTUnwrap(model.messages.last)

        XCTAssertFalse(model.actions(for: earlier).contains(.edit))
        XCTAssertFalse(model.isAvailable(.edit, for: earlier))
        XCTAssertTrue(model.actions(for: earlier).contains(.translate))
        model.selectMessage(earlier.id)
        model.perform(.edit, on: earlier.id)
        XCTAssertNil(model.editingMessageID)
        XCTAssertEqual(model.draft, "")

        XCTAssertTrue(model.actions(for: latest).contains(.edit))
        XCTAssertTrue(model.isAvailable(.edit, for: latest))
        model.selectMessage(latest.id)
        model.perform(.edit, on: latest.id)
        XCTAssertEqual(model.editingMessageID, latest.id)
        model.draft = "My edited newest message."
        XCTAssertTrue(model.submitDraft())
        XCTAssertEqual(model.messages[1], earlier)
        XCTAssertEqual(model.messages.last?.content, .text("My edited newest message."))
        XCTAssertEqual(model.messages.last?.communicationMethod, .text)
    }

    @MainActor
    func testPartnerReplyDoesNotTakeEditingEligibilityFromLatestLearnerMessage() {
        let learner = ConversationMessage(
            id: "learner", sender: .learner, communicationMethod: .text,
            content: .text("I love turtles.")
        )
        let partner = ConversationMessage(
            id: "partner", sender: .partner, communicationMethod: .text,
            content: .text("What do you like about them?")
        )
        let session = ConversationSession(
            id: "session", title: "乌龟", prompt: MockConversation.prompt,
            messages: [learner, partner], settings: ConversationSettings()
        )
        let model = ConversationViewModel(history: [session])
        XCTAssertTrue(model.openConversation(session.id))
        XCTAssertFalse(model.actions(for: partner).contains(.edit))
        XCTAssertFalse(model.isAvailable(.edit, for: partner))
        model.selectMessage(partner.id)
        model.perform(.edit, on: partner.id)
        XCTAssertNil(model.editingMessageID)

        XCTAssertTrue(model.isAvailable(.edit, for: learner))
        model.selectMessage(learner.id)
        model.perform(.edit, on: learner.id)
        model.draft = "I really love turtles."
        XCTAssertTrue(model.submitDraft())
        XCTAssertEqual(model.messages[0].content, .text("I really love turtles."))
        XCTAssertEqual(model.messages[1], partner)
    }

    @MainActor
    func testSystemModeIsTextOnlyOneShotAndCanBeCancelled() {
        let model = makeConversation()
        model.toggleSystemMessageMode()
        XCTAssertTrue(model.isSystemMessageMode)
        XCTAssertEqual(model.inputMode, .text)
        model.showVoiceInput()
        model.beginRecording()
        XCTAssertEqual(model.inputMode, .text)
        XCTAssertEqual(model.audio.recordingState, .idle)
        model.draft = " \n "
        XCTAssertFalse(model.submitDraft())
        XCTAssertTrue(model.isSystemMessageMode)
        XCTAssertEqual(model.messages, MockConversation.messages)
        model.draft = "Keep this text"
        model.toggleSystemMessageMode()
        XCTAssertFalse(model.isSystemMessageMode)
        XCTAssertEqual(model.inputMode, .voice)
        XCTAssertEqual(model.draft, "Keep this text")
        model.showTextInput()
        model.toggleSystemMessageMode()
        model.toggleSystemMessageMode()
        XCTAssertEqual(model.inputMode, .text)
    }

    @MainActor
    func testSystemRequestAddsOnlyTextSystemReplyAndUpdatesLocalSettings() {
        let model = makeConversation()
        model.toggleSystemMessageMode()
        model.draft = MockConversation.systemRequest
        XCTAssertTrue(model.submitDraft())
        XCTAssertEqual(model.messages.count, 4)
        let request = model.messages[2]
        let response = model.messages[3]
        XCTAssertEqual(request.sender, .learner)
        XCTAssertEqual(request.purpose, .system)
        XCTAssertEqual(request.communicationMethod, .text)
        XCTAssertEqual(request.content, .text(MockConversation.systemRequest))
        XCTAssertEqual(response.sender, .system)
        XCTAssertEqual(response.purpose, .system)
        XCTAssertEqual(response.content, .text(MockConversation.systemReply))
        XCTAssertEqual(response.communicationMethod, .text)
        XCTAssertNil(response.localAudio)
        XCTAssertTrue(request.actions.isEmpty)
        XCTAssertTrue(response.actions.isEmpty)
        XCTAssertFalse(model.isAvailable(.edit, for: model.messages[1]))
        XCTAssertEqual(model.settings.vocabulary, .simple)
        XCTAssertFalse(model.isSystemMessageMode)
        XCTAssertEqual(model.inputMode, .voice)
        XCTAssertTrue(model.draft.isEmpty)
        model.draft = "Back to practice"
        XCTAssertTrue(model.submitDraft())
        XCTAssertEqual(model.messages.last?.purpose, .conversation)
        XCTAssertEqual(model.messages.last?.communicationMethod, .text)
        XCTAssertEqual(model.messages[1].communicationMethod, .voice)
    }

    @MainActor
    func testSystemDemoQuestionsAndNavigationKeepModeTransient() {
        let model = makeConversation()
        model.settings.tone = .formal
        model.toggleSystemMessageMode()
        model.draft = MockConversation.systemSettingsQuestion
        XCTAssertTrue(model.submitDraft())
        guard let reply = model.messages.last, case let .text(answer) = reply.content else {
            return XCTFail("Expected a text system response")
        }
        XCTAssertTrue(answer.contains("正式"))
        XCTAssertTrue(answer.contains("本地示例"))
        let settings = model.settings
        model.toggleSystemMessageMode()
        model.draft = "An arbitrary question"
        XCTAssertTrue(model.submitDraft())
        XCTAssertEqual(model.settings, settings)
        guard let fallbackReply = model.messages.last, case let .text(fallback) = fallbackReply.content else {
            return XCTFail("Expected a text placeholder response")
        }
        XCTAssertTrue(fallback.contains("暂时无法回答任意问题"))
        model.toggleSystemMessageMode()
        model.draft = "Unsent system request"
        let saved = model.history
        model.leaveFeed()
        XCTAssertFalse(model.isSystemMessageMode)
        XCTAssertTrue(model.draft.isEmpty)
        XCTAssertEqual(model.history, saved)
    }

    @MainActor
    private func makeConversation() -> ConversationViewModel {
        let model = ConversationViewModel()
        model.suggestPrompt()
        model.startConversation()
        return model
    }
}
