import Foundation

/// A filter, not a classification: nil means aggregate across that dimension;
/// .unclassified means specifically unknown context. Matching requires every
/// specified dimension. Overlapping summaries must never be added together.
nonisolated struct PerformanceContext: Codable, Equatable, Hashable, Sendable {
    let topic: ContextTaxonomy.Topic?
    let languageTask: ContextTaxonomy.LanguageTask?
    let situation: ContextTaxonomy.Situation?
}

/// Rebuildable grammar performance evidence for a context, not a diagnosis of
/// weakness. The same category with an all-nil context provides its baseline.
/// The pure calculator consumes supplied records; persistence/classification and
/// adaptation are not wired into app flows.
nonisolated struct ContextualPerformanceSummary: Identifiable, Codable, Equatable, Sendable {
    struct Evidence: Codable, Equatable, Sendable {
        let conversationID: String
        let messageID: String
        let messageRevision: Int
        let logicalMessageID: String
        /// Practice/submission time, not evaluation or classification time.
        let submittedAt: Date
        let contextAnalysisID: String
        let grammarObservationID: String
        /// Exact scored/uncertain constructions used, not every construction in the message.
        let opportunityIDs: [String]
    }

    let id: String
    let computedAt: Date
    let calculationVersion: String
    let contextTaxonomyVersion: String
    /// Optional half-open [start, end) filter using submission timestamps.
    let reportingInterval: DateInterval?
    let context: PerformanceContext
    /// Stable category/subcategory, independent of display labels.
    let skill: ObservationCategory
    let correctOpportunities: Int
    let incorrectOpportunities: Int
    let uncertainOpportunities: Int
    /// All eligible attempts matching this context, including unanalyzed ones.
    let eligiblePracticeAttempts: Int
    let contextAnalyzedAttempts: Int
    let matchingPracticeAttempts: Int
    let grammarEvaluatedAttempts: Int
    let evaluatedConversationCount: Int
    /// Edits count fully as attempts but remain visibly related as evidence.
    let evaluatedLogicalMessageCount: Int
    let firstPracticeAt: Date?
    let lastPracticeAt: Date?
    let evidence: [Evidence]

    var accuracy: Double? {
        guard correctOpportunities > 0 || incorrectOpportunities > 0 else { return nil }
        return Double(correctOpportunities) / (Double(correctOpportunities) + Double(incorrectOpportunities))
    }
}
