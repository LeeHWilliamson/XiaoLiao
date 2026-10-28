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
        let newConversation = app.buttons["history.new"]
        XCTAssertTrue(newConversation.waitForExistence(timeout: 5))
        newConversation.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertFalse(start.isEnabled)
        app.buttons["conversation.suggest"].tap()
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

    @MainActor
    func testSettingsAreRestoredPerHistoryEntry() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["conversation.settings"].tap()
        let back = app.buttons["settings.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        app.buttons["settings.tone.warm"].tap()
        app.buttons["settings.vocabulary.complex"].tap()
        app.buttons["settings.replyLength.brief"].tap()
        back.tap()
        app.buttons["conversation.suggest"].tap()
        app.buttons["conversation.start"].tap()

        app.buttons["conversation.settings"].tap()
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["settings.tone.warm"].value as? String, "已选择")
        app.buttons["settings.tone.formal"].tap()
        back.tap()
        app.buttons["conversation.history"].tap()
        let selected = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND value == %@", "history.session.", "已选择")).firstMatch
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        let savedID = selected.identifier
        app.buttons["history.session.history-B"].tap()

        app.buttons["conversation.settings"].tap()
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["settings.tone.casual"].value as? String, "已选择")
        XCTAssertEqual(app.buttons["settings.vocabulary.medium"].value as? String, "已选择")
        XCTAssertEqual(app.buttons["settings.replyLength.medium"].value as? String, "已选择")
        back.tap()
        app.buttons["conversation.history"].tap()
        XCTAssertTrue(app.buttons[savedID].waitForExistence(timeout: 5))
        app.buttons[savedID].tap()
        app.buttons["conversation.settings"].tap()
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["settings.tone.formal"].value as? String, "已选择")
        XCTAssertEqual(app.buttons["settings.vocabulary.complex"].value as? String, "已选择")
        XCTAssertEqual(app.buttons["settings.replyLength.brief"].value as? String, "已选择")
    }

    @MainActor
    func testClosingHistoryPreservesNewConversationPrompt() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["conversation.suggest"].tap()
        let prompt = app.textViews["conversation.prompt"]
        let original = prompt.value as? String
        app.buttons["conversation.history"].tap()
        let close = app.buttons["history.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        XCTAssertEqual(prompt.value as? String, original)
        XCTAssertTrue(app.buttons["conversation.start"].isEnabled)
    }
}
