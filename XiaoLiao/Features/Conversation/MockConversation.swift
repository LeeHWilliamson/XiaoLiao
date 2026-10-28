enum MockConversation {
    static let systemRequest = "你能用更简单的词吗？"
    static let systemReply = "是的，我们现在可以用更简单的词。\n（本地示例）"
    static let systemSettingsQuestion = "当前对话设置是什么？"

    // Explicit fixtures, not an AI interpreter or an arbitrary intent parser.
    static func systemResponse(for request: String, settings: ConversationSettings) -> (text: String, vocabulary: ConversationSettings.Vocabulary?) {
        if request == systemRequest {
            return (systemReply, .simple)
        }
        if request == systemSettingsQuestion {
            return ("语气：\(settings.tone.title)\n用词难度：\(settings.vocabulary.title)\n回复长度：\(settings.replyLength.title)\n（本地示例）", nil)
        }
        return ("这是本地示例回复，暂时无法回答任意问题。你可以试试：“\(systemRequest)”", nil)
    }

    // The first row and B–J labels are the history fixtures shown in Figma.
    static var history: [ConversationSession] {
        (["乌龟"] + Array("BCDEFGHIJ").map(String.init)).enumerated().map { index, title in
            ConversationSession(
                id: index == 0 ? "history-turtles" : "history-\(title)",
                title: title,
                prompt: prompt,
                messages: messages,
                settings: ConversationSettings()
            )
        }
    }

    static let prompt = "我想和一位热情的生物学家聊聊革龟的生命周期。用简单的词语，问一些引导性的问题。"

    static let messages: [ConversationMessage] = [
        ConversationMessage(
            id: "mock-partner-audio",
            sender: .partner,
            communicationMethod: .voice,
            content: .audio(duration: 5, transcript: "Do you love turtles?"),
            mockTranslation: "我今天喝了杯咖啡"
        ),
        ConversationMessage(
            id: "mock-learner-text",
            sender: .learner,
            // The green Figma bubble displays the learner's spoken response as text.
            communicationMethod: .voice,
            content: .text("Yes, I also love turtles!"),
            mockTranslation: "我今天喝了杯咖啡"
        )
    ]
}
