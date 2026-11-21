import Foundation

/// One classification for an exact immutable message version. Intended tasks
/// may differ from a conversation's broad scenario and from grammatical outcome.
nonisolated struct MessageContextAnalysis: Identifiable, Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable {
        case explicitUser = "explicit-user"
        case conversationDefault = "conversation-default"
        case inferred
    }

    /// Reuses exact message/revision/text-source linkage, classification timestamp,
    /// and evaluator/method/rubric/taxonomy versions. Manual tagging uses .manual.
    /// Confidence remains nil unless genuinely supplied; it is not proficiency.
    let metadata: ObservationMetadata
    let source: Source
    /// Retain the conversation-level source record when broad defaults were used.
    let conversationContextID: String?
    let tags: ContextTags
    var id: String { metadata.id }
}

/// Broad scenario context, separate from judgments about individual messages.
/// Future consumers must not silently treat this as message-level certainty.
nonisolated struct ConversationContext: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let conversationID: String
    let recordedAt: Date
    let source: MessageContextAnalysis.Source
    let provenance: EvaluationProvenance
    let tags: ContextTags
}
