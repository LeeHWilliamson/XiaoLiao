import Foundation

/// One message-level vocabulary evaluation. Multiple contextual assessments
/// share a word/phrase occurrence instead of repeating its span and lemma.
/// This is not a complete token inventory or a vocabulary-frequency calculation.
nonisolated struct VocabularyObservation: Identifiable, Codable, Equatable, Sendable {
    enum UnitKind: String, Codable, Sendable {
        case word, phrase
    }

    enum Outcome: String, Codable, Sendable {
        case appropriate, inappropriate, uncertain, notEvaluated
    }

    struct Assessment: Codable, Equatable, Sendable {
        /// Assessment dimension, such as word choice, collocation, or register.
        /// A category/subcategory pair identifies one assessment within a usage.
        let category: ObservationCategory
        let outcome: Outcome
        let suggestedReplacement: String?
        let explanation: String?
        /// Optional confidence for this assessment in 0...1.
        let confidence: Double?
    }

    struct Usage: Identifiable, Codable, Equatable, Sendable {
        let id: String
        let unitKind: UnitKind
        let surfaceText: String
        /// Normalized lemma/form when available, distinct from the surface text.
        let lemma: String?
        let textSpan: ObservationTextSpan
        let assessments: [Assessment]
    }

    let metadata: ObservationMetadata
    let usages: [Usage]

    var id: String { metadata.id }
}
