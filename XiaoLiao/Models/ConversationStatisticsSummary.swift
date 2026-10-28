import Foundation

nonisolated struct StatisticsConfiguration: Codable, Equatable, Sendable {
    /// A configurable initial default, not a claim that 50 is a universal cutoff.
    let mattrWindowSize: Int
    let normalizationVersion: String
    init(mattrWindowSize: Int = 50) {
        self.mattrWindowSize = mattrWindowSize
        normalizationVersion = WordForm.version
    }
}

nonisolated struct GrammarMetricSummary: Codable, Equatable, Sendable {
    let category: GrammarObservation.TrackedCategory
    let correct: Int
    let incorrect: Int
    let uncertain: Int
    var scoredOpportunities: Int { correct + incorrect }
    var accuracy: Double? {
        scoredOpportunities == 0 ? nil : Double(correct) / Double(scoredOpportunities)
    }
}

nonisolated struct PracticeStatistics: Codable, Equatable, Sendable {
    /// Every submitted original/edit counts once, including unchanged text.
    let practiceAttempts: Int
    let attemptsWithText: Int
    let textAnalyzedAttempts: Int
    let grammarEvaluatedAttempts: Int
    let clauseAnalyzedAttempts: Int
    /// Nil means no text analysis, not zero activity.
    let wordCount: Int?
    let sentenceCount: Int?
    let clauseCount: Int?
    /// Only sentences belonging to attempts that also have clause analysis.
    let sentencesWithClauseAnalysis: Int
    let distinctWordForms: Int?
    let newlyObservedWordForms: Int?
    /// Calculated from ordered words in the available analyzed text, not averaged
    /// from message/conversation scores. Nil below the configured window size.
    let mattr: Double?
    let grammar: [GrammarMetricSummary]

    var clausesPerSentence: Double? {
        guard let clauseCount, sentencesWithClauseAnalysis > 0 else { return nil }
        return Double(clauseCount) / Double(sentencesWithClauseAnalysis)
    }
}

/// Rebuildable snapshot. It is not the authoritative message/analysis store.
nonisolated struct ConversationStatisticsSummary: Identifiable, Codable, Equatable, Sendable {
    let conversationID: String
    let statistics: PracticeStatistics
    var id: String { conversationID }
}

nonisolated struct DailyStatisticsSummary: Codable, Equatable, Sendable {
    let start: Date
    let end: Date
    let statistics: PracticeStatistics
}

nonisolated struct StatisticsSnapshot: Codable, Equatable, Sendable {
    static let calculationVersion = "practice-statistics-v2"
    let version: String
    let computedAt: Date
    let configuration: StatisticsConfiguration
    let timeZoneIdentifier: String
    let calendarIdentifier: String
    /// Optional half-open reporting interval [start, end).
    let interval: DateInterval?
    let overall: PracticeStatistics
    let conversations: [ConversationStatisticsSummary]
    /// Dates follow message submission time, never analysis/summary refresh time.
    let days: [DailyStatisticsSummary]
    /// All supplied history, even when the displayed statistics use a date range.
    let vocabularyHistory: [VocabularyHistoryEntry]
}
