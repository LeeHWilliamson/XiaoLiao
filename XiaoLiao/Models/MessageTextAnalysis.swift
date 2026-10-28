import Foundation

/// Structural text data for one exact message version, independent of judgments
/// about whether its grammar/vocabulary is correct.
nonisolated struct MessageTextAnalysis: Identifiable, Codable, Equatable, Sendable {
    struct Word: Codable, Equatable, Sendable {
        let surfaceText: String
        let textSpan: ObservationTextSpan
        var normalizedForm: String { WordForm.normalize(surfaceText) }
    }

    struct ClauseAnalysis: Codable, Equatable, Sendable {
        let count: Int
        let provenance: EvaluationProvenance
    }

    let metadata: ObservationMetadata
    let normalizationVersion: String
    /// Complete ordered word occurrences under the declared policy, including
    /// repetitions. Never deduplicate this array or fill it from selective judgments.
    let words: [Word]
    let sentenceSpans: [ObservationTextSpan]
    /// Nil means not evaluated. Zero is a supplied evaluation finding no clauses.
    let clauses: ClauseAnalysis?
    var id: String { metadata.id }

    enum ValidationError: Error { case invalidStructure }

    func validate(text: String) throws {
        guard normalizationVersion == WordForm.version else { throw ValidationError.invalidStructure }
        var previousEnd = 0
        for word in words {
            guard word.textSpan.lengthUTF16 > 0, word.textSpan.startUTF16 >= previousEnd,
                  let range = word.textSpan.range(in: text), String(text[range]) == word.surfaceText,
                  WordForm.isWord(word.surfaceText) else { throw ValidationError.invalidStructure }
            previousEnd = word.textSpan.startUTF16 + word.textSpan.lengthUTF16
        }
        previousEnd = 0
        for span in sentenceSpans {
            guard span.lengthUTF16 > 0, span.startUTF16 >= previousEnd, span.range(in: text) != nil else {
                throw ValidationError.invalidStructure
            }
            previousEnd = span.startUTF16 + span.lengthUTF16
        }
        // Every counted word belongs to exactly one non-overlapping sentence.
        var sentenceIndex = 0
        var occupiedSentences = Set<Int>()
        for word in words {
            while sentenceIndex < sentenceSpans.count,
                  sentenceSpans[sentenceIndex].startUTF16 + sentenceSpans[sentenceIndex].lengthUTF16 <= word.textSpan.startUTF16 {
                sentenceIndex += 1
            }
            guard sentenceIndex < sentenceSpans.count else { throw ValidationError.invalidStructure }
            let sentence = sentenceSpans[sentenceIndex]
            guard sentence.startUTF16 <= word.textSpan.startUTF16,
                  word.textSpan.startUTF16 + word.textSpan.lengthUTF16 <= sentence.startUTF16 + sentence.lengthUTF16 else {
                throw ValidationError.invalidStructure
            }
            occupiedSentences.insert(sentenceIndex)
        }
        guard occupiedSentences.count == sentenceSpans.count else { throw ValidationError.invalidStructure }
        if let clauses {
            let provenance = clauses.provenance
            guard clauses.count >= 0, !sentenceSpans.isEmpty || clauses.count == 0,
                  !provenance.evaluatorID.isEmpty, !provenance.evaluatorVersion.isEmpty,
                  !provenance.rubricVersion.isEmpty, !provenance.taxonomyVersion.isEmpty else {
                throw ValidationError.invalidStructure
            }
        }
    }
}

nonisolated enum WordForm {
    static let version = "latin-word-forms-v1"

    static func normalize(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "’", with: "'")
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    /// English-oriented lexical tokens: Latin letters/marks, with internal
    /// apostrophes/hyphens. Excludes punctuation, numbers, emoji and Chinese copy.
    /// Word forms stay distinct: run/runs/running are not lemmatized.
    static func isWord(_ text: String) -> Bool {
        normalize(text).range(of: "^\\p{Latin}[\\p{Latin}\\p{M}]*(?:['-]\\p{Latin}[\\p{Latin}\\p{M}]*)*$", options: .regularExpression) != nil
    }
}
