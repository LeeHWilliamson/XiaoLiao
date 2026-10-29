import XCTest

final class ConversationFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testVisibleSendButtonSubmitsTypedAndSystemMessagesWithoutReturn() {
        let app = XCUIApplication.isolatedHistoryApp()
        app.launch()
        app.buttons["conversation.suggest"].tap()
        app.buttons["conversation.start"].tap()
        app.buttons["conversation.keyboard"].tap()
        let draft = app.descendants(matching: .any)["conversation.draft"].firstMatch
        let send = app.buttons["conversation.sendText"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        XCTAssertFalse(send.isEnabled)
        draft.tap()
        draft.typeText("   ")
        XCTAssertFalse(send.isEnabled)
        let typedMessage = "Hello from the Send button."
        draft.typeText(typedMessage)
        XCTAssertTrue(send.isEnabled)
        send.tap()
        let sent = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                                                    "message.", typedMessage)).firstMatch
        XCTAssertTrue(sent.waitForExistence(timeout: 5))
        XCTAssertFalse(send.isEnabled)
        XCTAssertTrue(app.buttons["conversation.microphone"].isEnabled)

        app.buttons["conversation.systemMode"].tap()
        XCTAssertFalse(app.buttons["conversation.microphone"].isEnabled)
        let systemRequest = "Please use simpler words."
        draft.tap()
        draft.typeText(systemRequest)
        XCTAssertTrue(send.isEnabled)
        send.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", systemRequest))
            .firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["conversation.systemMode"].value as? String, "未选择")
    }

    @MainActor
    private func fixtureBubble(_ suffix: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@",
                                         "message.", "." + suffix)).firstMatch
    }

    @MainActor
    func testUnifiedMenuKeepsStatisticsSelectionWhenReopeningTheSameDestination() {
        let app = XCUIApplication.isolatedHistoryApp()
        app.launchEnvironment["XIAOLIAO_UI_TEST_STATS_FIXTURE"] = "1"
        app.launch()
        XCTAssertEqual(app.buttons.matching(identifier: "navigation.menu").count, 1)
        XCTAssertFalse(app.buttons["conversation.statistics"].exists)
        XCTAssertFalse(app.buttons["conversation.settings"].exists)
        openMenuDestination("menu.statistics", in: app)
        let articles = app.buttons["stats.grammar.category.article-usage"]
        XCTAssertTrue(articles.waitForExistence(timeout: 5))
        articles.tap()
        let selected = app.staticTexts["stats.grammar.selected"]
        scrollTo(selected, in: app)
        XCTAssertTrue(selected.label.contains("冠词"))
        openMenuDestination("menu.statistics", in: app)
        XCTAssertTrue(selected.label.contains("冠词"))
        openMenuDestination("menu.settings", in: app)
        XCTAssertTrue(app.buttons["settings.tone.casual"].waitForExistence(timeout: 5))
        openMenu(in: app)
        let conversationStats = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "menu.sessionStatistics.")).firstMatch
        XCTAssertTrue(conversationStats.exists)
        XCTAssertFalse(conversationStats.isEnabled)
        app.buttons["menu.close"].tap()
        XCTAssertTrue(app.buttons["settings.tone.casual"].exists)
    }

    @MainActor
    func testSentTextAutomaticallyAppearsInOverallSentenceStatisticsAfterRelaunch() {
        let app = XCUIApplication.isolatedHistoryApp()
        app.launch()
        app.buttons["conversation.suggest"].tap()
        app.buttons["conversation.start"].tap()
        app.buttons["conversation.keyboard"].tap()
        let draft = app.descendants(matching: .any)["conversation.draft"].firstMatch
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        draft.tap()
        draft.typeText("Run runs running.\n")
        openMenuDestination("menu.statistics", in: app)
        let sentence = app.descendants(matching: .any)["stats.activity.sentences"].firstMatch
        XCTAssertTrue(app.buttons["stats.grammar.category.verb-tense"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["stats.empty"].exists)
        scrollTo(sentence, in: app)
        XCTAssertTrue(sentence.isHittable)
        XCTAssertTrue(sentence.label.contains("1"))
        XCTAssertFalse(sentence.label.contains("—"))
        app.terminate()
        app.launch()
        openMenuDestination("menu.statistics", in: app)
        XCTAssertTrue(app.buttons["stats.grammar.category.verb-tense"].waitForExistence(timeout: 5))
        scrollTo(sentence, in: app)
        XCTAssertTrue(sentence.isHittable)
        XCTAssertTrue(sentence.label.contains("1"))
    }

    @MainActor
    func testOverallStatisticsEmptySelectionAndReturnPreserveThePrompt() {
        let app = XCUIApplication.isolatedHistoryApp()
        app.launch()
        app.buttons["conversation.suggest"].tap()
        let prompt = app.textViews["conversation.prompt"].value as? String
        openMenu(in: app)
        let statistics = app.buttons["menu.statistics"]
        XCTAssertTrue(statistics.isEnabled)
        statistics.tap()
        XCTAssertTrue(app.staticTexts["stats.empty"].waitForExistence(timeout: 5))
        let category = app.buttons["stats.grammar.category.tense-consistency"]
        XCTAssertTrue(category.exists)
        category.tap()
        let trendLabel = app.staticTexts["stats.grammar.selected"]
        scrollTo(trendLabel, in: app)
        XCTAssertTrue(trendLabel.label.contains("时态一致性"))
        returnToConversation(in: app)
        XCTAssertTrue(app.buttons["conversation.start"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textViews["conversation.prompt"].value as? String, prompt)
        XCTAssertTrue(app.buttons["conversation.start"].isEnabled)
    }

    @MainActor
    func testPopulatedOverallStatisticsSelectionAndActivityTable() {
        let app = XCUIApplication.isolatedHistoryApp()
        app.launchEnvironment["XIAOLIAO_UI_TEST_STATS_FIXTURE"] = "1"
        app.launch()
        openMenuDestination("menu.statistics", in: app)
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
    private func openMenu(in app: XCUIApplication) {
        let menu = app.buttons["navigation.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        XCTAssertTrue(app.buttons["menu.close"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func openMenuDestination(_ identifier: String, in app: XCUIApplication) {
        openMenu(in: app)
        let destination = app.buttons[identifier]
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        destination.tap()
        XCTAssertTrue(app.buttons["navigation.menu"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func returnToConversation(in app: XCUIApplication) {
        openMenu(in: app)
        let selected = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND value == %@",
                                                        "menu.session.", "已选择")).firstMatch
        if selected.exists {
            selected.tap()
        } else {
            app.buttons["menu.new"].tap()
        }
        XCTAssertTrue(app.buttons["navigation.menu"].waitForExistence(timeout: 5))
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
        openMenuDestination("menu.statistics", in: app)
        XCTAssertTrue(app.buttons["navigation.menu"].waitForExistence(timeout: 5))
        returnToConversation(in: app)
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
        XCTAssertFalse(app.buttons["conversation.restartRecording"].exists)
        XCTAssertFalse(app.buttons["conversation.recordingControl"].exists)
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

        openMenu(in: app)
        let newConversation = app.buttons["menu.new"]
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
        openMenuDestination("menu.settings", in: app)
        let back = app.buttons["navigation.menu"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        app.buttons["settings.tone.warm"].tap()
        app.buttons["settings.vocabulary.complex"].tap()
        app.buttons["settings.replyLength.brief"].tap()
        returnToConversation(in: app)
        app.buttons["conversation.suggest"].tap()
        app.buttons["conversation.start"].tap()

        openMenuDestination("menu.settings", in: app)
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["settings.tone.warm"].value as? String, "已选择")
        app.buttons["settings.tone.formal"].tap()
        returnToConversation(in: app)
        openMenu(in: app)
        let selected = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND value == %@", "menu.session.", "已选择")).firstMatch
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        let savedID = selected.identifier
        app.buttons["menu.new"].tap()
        app.buttons["conversation.suggest"].tap()
        app.buttons["conversation.start"].tap()

        openMenuDestination("menu.settings", in: app)
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["settings.tone.casual"].value as? String, "已选择")
        XCTAssertEqual(app.buttons["settings.vocabulary.medium"].value as? String, "已选择")
        XCTAssertEqual(app.buttons["settings.replyLength.medium"].value as? String, "已选择")
        returnToConversation(in: app)
        openMenu(in: app)
        XCTAssertTrue(app.buttons[savedID].waitForExistence(timeout: 5))
        app.buttons[savedID].tap()
        openMenuDestination("menu.settings", in: app)
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
        openMenu(in: app)
        let close = app.buttons["menu.close"]
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
        openMenuDestination("menu.settings", in: app)
        let back = app.buttons["navigation.menu"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        app.buttons["settings.tone.formal"].tap()
        app.buttons["settings.replyLength.brief"].tap()
        returnToConversation(in: app)
        openMenu(in: app)
        let selected = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND value == %@", "menu.session.", "已选择")).firstMatch
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        let savedID = selected.identifier
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["navigation.menu"].waitForExistence(timeout: 5))
        openMenu(in: app)
        let saved = app.buttons[savedID]
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.tap()
        XCTAssertTrue(fixtureBubble("learner-text", in: app).waitForExistence(timeout: 5))
        openMenuDestination("menu.settings", in: app)
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
