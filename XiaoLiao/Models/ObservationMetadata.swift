import Foundation

/// Shared once per message-level evaluation, rather than on every word/check.
/// Absence of an observation means evaluation has not been performed; an empty
/// result array means an evaluation found no applicable entries.
nonisolated struct ObservationMetadata: Identifiable, Codable, Equatable, Sendable {
    enum TextSource: String, Codable, Sendable {
        case messageText, speechTranscription
    }

    let id: String
    /// ID of the exact Message version evaluated, not its logicalMessageID.
    let messageID: String
    let conversationID: String
    /// Revision number of that same message record, retained for provenance.
    let messageRevision: Int
    let textSource: TextSource
    let evaluatedAt: Date
    let provenance: EvaluationProvenance
    /// Optional evaluator metadata in 0...1, not a guarantee of accuracy.
    let confidence: Double?
}

nonisolated struct EvaluationProvenance: Codable, Equatable, Sendable {
    enum Method: String, Codable, Sendable {
        case ruleBased, languageModel, manual, hybrid
    }

    let method: Method
    let evaluatorID: String
    let evaluatorVersion: String
    let rubricVersion: String
    let taxonomyVersion: String
}

/// Stable taxonomy codes, independent of display labels and translations.
/// Categories are data, not a hardcoded list of all future metrics.
nonisolated struct ObservationCategory: Codable, Equatable, Hashable, Sendable {
    let categoryID: String
    let subcategoryID: String?
}

/// Range in the exact text source/revision named by ObservationMetadata.
/// Offsets and lengths count UTF-16 code units, not Swift Characters or bytes.
/// A zero-length range can identify an insertion point for omitted text.
/// ConversationSession validates these against the exact source before storage.
nonisolated struct ObservationTextSpan: Codable, Equatable, Hashable, Sendable {
    let startUTF16: Int
    let lengthUTF16: Int
}
