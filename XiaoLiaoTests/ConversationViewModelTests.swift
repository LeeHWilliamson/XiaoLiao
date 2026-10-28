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
    private func makeConversation() -> ConversationViewModel {
        let model = ConversationViewModel()
        model.suggestPrompt()
        model.startConversation()
        return model
    }
}
