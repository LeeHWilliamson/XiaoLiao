import Foundation

/// One message-level grammar evaluation, containing only applicable rule checks.
/// Counts, accuracy metrics, and error lists can later be derived from these
/// opportunities; no duplicated summary counters or evaluator logic live here.
nonisolated struct GrammarObservation: Identifiable, Codable, Equatable, Sendable {
    /// Statistics taxonomy. Other category codes remain valid observations but
    /// do not silently enter the dashboard's tracked metrics.
    enum TrackedCategory: String, CaseIterable, Codable, Equatable, Sendable {
        case verbTense = "verb-tense"
        case tenseConsistency = "tense-consistency"
        case articles = "article-usage"
        case prepositions = "preposition-usage"
        case subjectVerbAgreement = "subject-verb-agreement"

        var observationCategory: ObservationCategory {
            ObservationCategory(categoryID: rawValue, subcategoryID: nil)
        }
    }
    enum Outcome: String, Codable, Sendable {
        case correct, incorrect, uncertain
    }

    struct Opportunity: Identifiable, Codable, Equatable, Sendable {
        let id: String
        /// One specific rule check at a span. The same span may have distinct
        /// opportunities for different rules; it is not one entry per metric.
        let category: ObservationCategory
        let textSpan: ObservationTextSpan
        let outcome: Outcome
        let suggestedCorrection: String?
        let explanation: String?
        /// Optional confidence for this check in 0...1.
        let confidence: Double?
    }

    let metadata: ObservationMetadata
    let opportunities: [Opportunity]

    var id: String { metadata.id }
}
