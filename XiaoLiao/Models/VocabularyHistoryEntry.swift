import Foundation

/// First observed use within the available analyzed learner history. This does
/// not assert when a person learned a word or that missing transcripts lack it.
nonisolated struct VocabularyHistoryEntry: Identifiable, Codable, Equatable, Sendable {
    let wordForm: String
    let firstUsedAt: Date
    let firstMessageID: String
    let firstConversationID: String
    var id: String { wordForm }
}
