import XCTest
@testable import XiaoLiao

final class ConversationHistoryTests: XCTestCase {
    @MainActor
    func testRequiredPromptCreatesHistoryOnlyAfterValidation() throws {
        let model = ConversationViewModel(history: [])
        model.prompt = " \n "
        XCTAssertFalse(model.startConversation())
        XCTAssertTrue(model.history.isEmpty)
        XCTAssertNil(model.activeSessionID)

        model.suggestPrompt()
        model.settings.tone = .warm
        XCTAssertTrue(model.startConversation())
        let session = try XCTUnwrap(model.history.first)
        XCTAssertEqual(session.id, model.activeSessionID)
        XCTAssertEqual(session.title, "乌龟")
        XCTAssertEqual(session.prompt, MockConversation.prompt)
        XCTAssertEqual(session.settings.tone, .warm)
    }

    @MainActor
    func testEachSessionRestoresItsOwnEditedMessagesAndSettings() throws {
        let model = ConversationViewModel(history: [])
        model.prompt = "海龟的生活"
        model.startConversation()
        let turtles = try XCTUnwrap(model.activeSessionID)
        model.settings.tone = .warm
        model.settings.replyLength = .brief
        let messageID = model.messages[1].id
        model.selectMessage(messageID)
        model.perform(.edit, on: messageID)
        model.draft = "I saw a sea turtle."
        model.submitDraft()

        model.prepareNewConversation()
        model.prompt = "点咖啡"
        model.startConversation()
        let coffee = try XCTUnwrap(model.activeSessionID)
        model.settings.tone = .formal
        model.settings.vocabulary = .complex

        XCTAssertTrue(model.openConversation(turtles))
        XCTAssertEqual(model.prompt, "海龟的生活")
        XCTAssertEqual(model.messages[1].content, .text("I saw a sea turtle."))
        XCTAssertEqual(model.settings.tone, .warm)
        XCTAssertEqual(model.settings.replyLength, .brief)
        XCTAssertEqual(model.settings.vocabulary, .medium)

        XCTAssertTrue(model.openConversation(coffee))
        XCTAssertEqual(model.messages[1].content, .text("Yes, I also love turtles!"))
        XCTAssertEqual(model.settings.tone, .formal)
        XCTAssertEqual(model.settings.vocabulary, .complex)
        XCTAssertEqual(model.settings.replyLength, .medium)
        XCTAssertEqual(model.history.count, 2)
    }

    @MainActor
    func testNewConversationClearsDraftWithoutChangingArchivedSession() throws {
        let model = ConversationViewModel(history: [])
        model.suggestPrompt()
        model.startConversation()
        model.settings.tone = .formal
        let saved = try XCTUnwrap(model.history.first)
        model.selectMessage(model.messages[1].id)
        model.perform(.edit, on: model.messages[1].id)
        model.draft = "An unfinished edit"

        model.prepareNewConversation()
        XCTAssertNil(model.activeSessionID)
        XCTAssertNil(model.selectedMessageID)
        XCTAssertNil(model.editingMessageID)
        XCTAssertTrue(model.prompt.isEmpty)
        XCTAssertTrue(model.messages.isEmpty)
        XCTAssertTrue(model.draft.isEmpty)
        XCTAssertFalse(model.canStart)
        XCTAssertEqual(model.settings, ConversationSettings())
        model.settings.vocabulary = .simple
        XCTAssertEqual(model.history, [saved])
    }

    @MainActor
    func testRestoringSessionClearsTransientUIAndDoesNotDuplicateHistory() throws {
        let model = ConversationViewModel(history: [])
        model.suggestPrompt()
        model.startConversation()
        let id = try XCTUnwrap(model.activeSessionID)
        model.draft = "Hello!"
        model.submitDraft()
        model.selectMessage(model.messages[0].id)
        model.perform(.transcribe, on: model.messages[0].id)
        model.inputMode = .text
        model.draft = "Unsent"

        XCTAssertTrue(model.openConversation(id))
        XCTAssertEqual(model.messages.count, 3)
        XCTAssertTrue(model.details.isEmpty)
        XCTAssertTrue(model.draft.isEmpty)
        XCTAssertEqual(model.inputMode, .voice)
        XCTAssertNil(model.selectedMessageID)
        XCTAssertEqual(model.history.count, 1)
    }

    @MainActor
    func testUnknownHistoryIDLeavesCurrentConversationUntouched() {
        let model = ConversationViewModel(history: [])
        model.suggestPrompt()
        model.startConversation()
        model.settings.replyLength = .brief
        model.draft = "Keep this draft"
        let history = model.history
        let id = model.activeSessionID
        let messages = model.messages

        XCTAssertFalse(model.openConversation("missing"))
        XCTAssertEqual(model.activeSessionID, id)
        XCTAssertEqual(model.history, history)
        XCTAssertEqual(model.messages, messages)
        XCTAssertEqual(model.draft, "Keep this draft")
    }
}
