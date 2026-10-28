struct ConversationSession: Identifiable, Equatable {
    let id: String
    let title: String
    let prompt: String
    var messages: [ConversationMessage]
    var settings: ConversationSettings
}
