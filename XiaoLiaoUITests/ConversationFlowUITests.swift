import XCTest

final class ConversationFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testNavigationAndContextualActions() {
        let app = XCUIApplication()
        app.launch()
        let start = app.buttons["conversation.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertFalse(start.isEnabled)
        app.buttons["conversation.suggest"].tap()
        XCTAssertTrue(start.isEnabled)
        start.tap()

        let audio = app.buttons["message.mock-partner-audio"]
        let learner = app.buttons["message.mock-learner-text"]
        let learnerTranslation = app.buttons["action.mock-learner-text.translate"]
        let transcript = app.buttons["action.mock-partner-audio.transcribe"]
        XCTAssertTrue(audio.waitForExistence(timeout: 5))
        XCTAssertTrue(learner.exists)
        XCTAssertFalse(learnerTranslation.exists)
        XCTAssertFalse(transcript.exists)
        learner.tap()
        XCTAssertTrue(learnerTranslation.exists)
        XCTAssertFalse(app.buttons["action.mock-learner-text.play"].isEnabled)
        learnerTranslation.tap()
        XCTAssertTrue(app.staticTexts["我今天喝了杯咖啡"].exists)
        audio.tap()
        XCTAssertFalse(learnerTranslation.exists)
        XCTAssertTrue(transcript.exists)
        transcript.tap()
        XCTAssertTrue(app.staticTexts["Do you love turtles?"].exists)
        audio.tap()
        XCTAssertFalse(transcript.exists)

        app.buttons["conversation.history"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertTrue(start.isEnabled)
        start.tap()
        XCTAssertTrue(audio.waitForExistence(timeout: 5))
        XCTAssertFalse(transcript.exists)
        XCTAssertFalse(app.staticTexts["Do you love turtles?"].exists)
    }

    @MainActor
    func testEditingUsesTextComposerAndCanReturnToVoiceMode() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["conversation.suggest"].tap()
        app.buttons["conversation.start"].tap()
        let learner = app.buttons["message.mock-learner-text"]
        XCTAssertTrue(learner.waitForExistence(timeout: 5))
        learner.tap()
        app.buttons["action.mock-learner-text.edit"].tap()
        let draft = app.descendants(matching: .any)["conversation.draft"].firstMatch
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        XCTAssertEqual(draft.value as? String, "Yes, I also love turtles!")
        app.buttons["conversation.microphone"].tap()
        XCTAssertTrue(app.buttons["conversation.keyboard"].exists)
        XCTAssertFalse(draft.exists)
    }
}
