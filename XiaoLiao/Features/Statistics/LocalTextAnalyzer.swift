import Foundation
import NaturalLanguage

/// Explicit local extraction only. No grammar judgments, clause guesses, speech
/// recognition, AI calls or automatic work on every keystroke.
nonisolated enum LocalTextAnalyzer {
    static func analyze(_ message: Message, at date: Date = Date()) throws -> MessageTextAnalysis? {
        guard message.countsAsPractice, let source = message.statisticsText else { return nil }
        let text = source.text
        let words = NLTokenizer(unit: .word)
        words.setLanguage(.english)
        words.string = text
        let occurrences = words.tokens(for: text.startIndex..<text.endIndex).compactMap { range -> MessageTextAnalysis.Word? in
            let surface = String(text[range])
            guard WordForm.isWord(surface) else { return nil }
            let span = NSRange(range, in: text)
            return .init(surfaceText: surface, textSpan: .init(startUTF16: span.location, lengthUTF16: span.length))
        }
        let sentences = NLTokenizer(unit: .sentence)
        sentences.setLanguage(.english)
        sentences.string = text
        var spans: [ObservationTextSpan] = []
        var wordIndex = 0
        for range in sentences.tokens(for: text.startIndex..<text.endIndex) {
            let span = NSRange(range, in: text)
            let beginning = wordIndex
            while wordIndex < occurrences.count, occurrences[wordIndex].textSpan.startUTF16 < span.location + span.length {
                wordIndex += 1
            }
            // Punctuation/numeral/Chinese-only units do not count as English practice sentences.
            if wordIndex > beginning { spans.append(.init(startUTF16: span.location, lengthUTF16: span.length)) }
        }
        let analysis = MessageTextAnalysis(
            metadata: ObservationMetadata(id: UUID().uuidString, messageID: message.id,
                                          conversationID: message.conversationID, messageRevision: message.revision,
                                          textSource: source.source, evaluatedAt: date,
                                          provenance: EvaluationProvenance(method: .ruleBased, evaluatorID: "apple-natural-language",
                                              evaluatorVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                                              rubricVersion: "sentence-tokenization-v1", taxonomyVersion: WordForm.version), confidence: nil),
            normalizationVersion: WordForm.version, words: occurrences, sentenceSpans: spans, clauses: nil
        )
        try analysis.validate(text: text)
        return analysis
    }
}
