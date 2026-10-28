import XCTest

final class ConversationFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func fixtureBubble(_ suffix: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@",
                                         "message.", "." + suffix)).firstMatch
    }

    @MainActor
    func testOverallStatisticsEmptySelectionAndReturnPreserveThePrompt() {
        let app = XCUIApplication.isolatedHistoryApp()
        app.launch()
        app.buttons["conversation.suggest"].tap()
        let prompt = app.textViews["conversation.prompt"].value as? String
        let statistics = app.buttons["conversation.statistics"]
        XCTAssertTrue(statistics.isEnabled)
        statistics.tap()
        XCTAssertTrue(app.staticTexts["stats.empty"].waitForExistence(timeout: 5))
        let category = app.buttons["stats.grammar.category.tense-consistency"]
        XCTAssertTrue(category.exists)
        category.tap()
        let trendLabel = app.staticTexts["stats.grammar.selected"]
        scrollTo(trendLabel, in: app)
        XCTAssertTrue(trendLabel.label.contains("时态一致性"))
        app.buttons["stats.back"].tap()
        XCTAssertTrue(app.buttons["conversation.start"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textViews["conversation.prompt"].value as? String, prompt)
        XCTAssertTrue(app.buttons["conversation.start"].isEnabled)
    }

    @MainActor
    func testPopulatedOverallStatisticsSelectionAndActivityTable() {
        let app = XCUIApplication.isolatedHistoryApp()
        app.launchEnvironment["XIAOLIAO_UI_TEST_STATS_FIXTURE"] = "1"
        app.launch()
        app.buttons["conversation.statistics"].tap()
        let articles = app.buttons["stats.grammar.category.article-usage"]
        XCTAssertTrue(articles.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["stats.empty"].exists)
        articles.tap()
        scrollTo(app.staticTexts["stats.grammar.selected"], in: app)
        XCTAssertTrue(app.staticTexts["stats.grammar.selected"].label.contains("冠词"))
        let activity = app.descendants(matching: .any)["stats.activity.clausesPerSentence"].firstMatch
        for _ in 0..<8 {
            if activity.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(activity.isHittable)
        XCTAssertFalse(activity.label.contains("—"))
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.isHittable { return }
            app.swipeUp()
        }
    }

    @MainActor
    func testOverallStatisticsOpenedFromFeedReturnsToTheSameConversation() {
        let app = XCUIApplication.isolatedHistoryApp()
        app.launch()
        app.buttons["conversation.suggest"].tap()
        app.buttons["conversation.start"].tap()
        let learner = fixtureBubble("learner-text", in: app)
        XCTAssertTrue(learner.waitForExistence(timeout: 5))
        let messageID = learner.identifier
        app.buttons["conversation.statistics"].tap()
        XCTAssertTrue(app.buttons["stats.back"].waitForExistence(timeout: 5))
        app.buttons["stats.back"].tap()
        XCTAssertTrue(app.buttons[messageID].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["conversation.record"].isEnabled)
    }

    @MainActor
    func testNavigationAndContextualActions() {
        let app = XCUIApplication.isolatedHistoryApp()
        app.launch()
        let start = app.buttons["conversation.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertFalse(start.isEnabled)
        app.buttons["conversation.suggest"].tap()
        XCTAssertTrue(start.isEnabled)
        start.tap()

        let audio = fixtureBubble("partner-audio", in: app)
        let learner = fixtureBubble("learner-text", in: app)
        XCTAssertTrue(audio.waitForExistence(timeout: 5))
        XCTAssertTrue(learner.exists)
        let learnerID = String(learner.identifier.dropFirst("message.".count))
        let audioID = String(audio.identifier.dropFirst("message.".count))
        let learnerTranslation = app.buttons["action.\(learnerID).translate"]
        let transcript = app.buttons["action.\(audioID).transcribe"]
        XCTAssertTrue(app.buttons["conversation.record"].isEnabled)
        XCTAssertFalse(app.buttons["conversation.pauseRecording"].exists)
        XCTAssertFalse(app.buttons["conversation.sendRecording"].exists)
        XCTAssertFalse(learnerTranslation.exists)
        XCTAssertFalse(transcript.exists)
        learner.tap()
        XCTAssertTrue(learnerTranslation.exists)
        XCTAssertFalse(app.buttons["action.\(learnerID).play"].isEnabled)
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
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", ".transcribe")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Do you love turtles?"].exists)
    }

    @MainActor
    func testEditingUsesTextComposerAndCanReturnToVoiceMode() {
        let app = XCUIApplication.isolatedHistoryApp()
        app.launch()
        app.buttons["conversation.suggest"].tap()
        app.buttons["conversation.start"].tap()
        let learner = fixtureBubble("learner-text", in: app)
        XCTAssertTrue(learner.waitForExistence(timeout: 5))
        let learnerID = String(learner.identifier.dropFirst("message.".count))
        learner.tap()
        app.buttons["action.\(learnerID).edit"].tap()
        let draft = app.descendants(matching: .any)["conversation.draft"].firstMatch
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        XCTAssertEqual(draft.value as? String, "Yes, I also love turtles!")
        app.buttons["conversation.microphone"].tap()
        XCTAssertTrue(app.buttons["conversation.keyboard"].exists)
        XCTAssertFalse(draft.exists)
    }

    @MainActor
    func testSettingsAreRestoredPerHistoryEntry() {
        let app = XCUIApplication.isolatedHistoryApp()
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
        app.buttons["history.new"].tap()
        app.buttons["conversation.suggest"].tap()
        app.buttons["conversation.start"].tap()

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
        let app = XCUIApplication.isolatedHistoryApp()
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

    @MainActor
    func testHistoryAndSettingsSurviveAppTermination() {
        let app = XCUIApplication.isolatedHistoryApp()
        app.launch()
        app.buttons["conversation.suggest"].tap()
        app.buttons["conversation.start"].tap()
        app.buttons["conversation.settings"].tap()
        let back = app.buttons["settings.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        app.buttons["settings.tone.formal"].tap()
        app.buttons["settings.replyLength.brief"].tap()
        back.tap()
        app.buttons["conversation.history"].tap()
        let selected = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND value == %@", "history.session.", "已选择")).firstMatch
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        let savedID = selected.identifier
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["conversation.history"].waitForExistence(timeout: 5))
        app.buttons["conversation.history"].tap()
        let saved = app.buttons[savedID]
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.tap()
        XCTAssertTrue(fixtureBubble("learner-text", in: app).waitForExistence(timeout: 5))
        app.buttons["conversation.settings"].tap()
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["settings.tone.formal"].value as? String, "已选择")
        XCTAssertEqual(app.buttons["settings.replyLength.brief"].value as? String, "已选择")
    }

    @MainActor
    func testSystemModeToggleTextOnlyAndOneMessageReset() {
        let app = XCUIApplication.isolatedHistoryApp()
        app.launch()
        app.buttons["conversation.suggest"].tap()
        app.buttons["conversation.start"].tap()
        let toggle = app.buttons["conversation.systemMode"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "已选择")
        XCTAssertFalse(app.buttons["conversation.microphone"].isEnabled)
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "未选择")
        XCTAssertTrue(app.buttons["conversation.record"].exists)
        toggle.tap()
        let draft = app.descendants(matching: .any)["conversation.draft"].firstMatch
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        draft.tap()
        draft.typeText("help\n")
        let response = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "暂时无法回答任意问题")).firstMatch
        XCTAssertTrue(response.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "未选择")
        XCTAssertTrue(app.buttons["conversation.record"].isEnabled)
    }
}

extension XCUIApplication {
    @MainActor
    static func isolatedHistoryApp() -> XCUIApplication {
        let app = XCUIApplication()
        // A unique durable store for each test; relaunches of this instance reuse it.
        app.launchEnvironment["XIAOLIAO_UI_TEST_STORE"] = UUID().uuidString
        return app
    }
}
