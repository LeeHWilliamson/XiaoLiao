enum MockConversation {
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
