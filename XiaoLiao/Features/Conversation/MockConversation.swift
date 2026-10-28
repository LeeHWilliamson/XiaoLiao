enum MockConversation {
    static let prompt = "我想和一位热情的生物学家聊聊革龟的生命周期。用简单的词语，问一些引导性的问题。"

    static let messages: [ConversationMessage] = [
        ConversationMessage(
            id: "mock-partner-audio",
            content: .audio(duration: 5, transcript: "Do you love turtles?"),
            mockTranslation: "我今天喝了杯咖啡"
        ),
        ConversationMessage(
            id: "mock-learner-text",
            content: .text("Yes, I also love turtles!"),
            mockTranslation: "我今天喝了杯咖啡"
        )
    ]
}
