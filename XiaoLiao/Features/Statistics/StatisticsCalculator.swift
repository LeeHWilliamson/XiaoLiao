import Foundation

/// Pure, repeatable extraction from supplied records. Call away from the UI
/// actor for large histories. Rebuilding never appends duplicate activity.
nonisolated enum StatisticsCalculator {
    enum CalculationError: Error { case invalidConfiguration, duplicateIdentity, countOverflow }

    private struct Attempt {
        let message: Message
        let text: MessageTextAnalysis?
        let grammar: GrammarObservation?
    }

    static func snapshot(sessions: [ConversationSession], configuration: StatisticsConfiguration = .init(),
                         interval: DateInterval? = nil, calendar: Calendar = .current,
                         computedAt: Date = Date()) throws -> StatisticsSnapshot {
        guard configuration.mattrWindowSize > 0, configuration.normalizationVersion == WordForm.version,
              computedAt.timeIntervalSince1970.isFinite,
              interval.map({ $0.start.timeIntervalSince1970.isFinite && $0.end.timeIntervalSince1970.isFinite }) ?? true else {
            throw CalculationError.invalidConfiguration
        }
        guard Set(sessions.map(\.id)).count == sessions.count else { throw CalculationError.duplicateIdentity }
        var attempts: [Attempt] = []
        var seenIDs = Set<String>()
        for session in sessions {
            try session.validate()
            let analyses = Dictionary(uniqueKeysWithValues: session.textAnalyses.map { ($0.metadata.messageID, $0) })
            let grammar = Dictionary(uniqueKeysWithValues: session.grammarObservations.map { ($0.metadata.messageID, $0) })
            for message in session.messages {
                guard seenIDs.insert(message.id).inserted else { throw CalculationError.duplicateIdentity }
                guard message.countsAsPractice else { continue }
                attempts.append(Attempt(message: message, text: analyses[message.id], grammar: grammar[message.id]))
            }
        }
        attempts.sort { lhs, rhs in
            if lhs.message.createdAt != rhs.message.createdAt { return lhs.message.createdAt < rhs.message.createdAt }
            if lhs.message.conversationID != rhs.message.conversationID { return lhs.message.conversationID < rhs.message.conversationID }
            return lhs.message.id < rhs.message.id
        }
        // Build first use from ALL supplied history before applying a reporting range.
        // An older late transcription can move first use back to its submission date.
        var firstUses: [String: VocabularyHistoryEntry] = [:]
        for attempt in attempts {
            for word in attempt.text?.words ?? [] where firstUses[word.normalizedForm] == nil {
                firstUses[word.normalizedForm] = VocabularyHistoryEntry(wordForm: word.normalizedForm,
                    firstUsedAt: attempt.message.createdAt, firstMessageID: attempt.message.id,
                    firstConversationID: attempt.message.conversationID)
            }
        }
        let history = firstUses.values.sorted {
            $0.firstUsedAt == $1.firstUsedAt ? $0.wordForm < $1.wordForm : $0.firstUsedAt < $1.firstUsedAt
        }
        let selected = attempts.filter { attempt in
            interval.map { attempt.message.createdAt >= $0.start && attempt.message.createdAt < $0.end } ?? true
        }
        // Each first-use entry belongs to exactly one version. This lookup avoids
        // scanning the vocabulary inventory for every conversation or day.
        let newWordsByMessage = Dictionary(grouping: history, by: \.firstMessageID).mapValues(\.count)
        let byConversation = Dictionary(grouping: selected, by: { $0.message.conversationID })
        let conversations = try sessions.map { session in
            ConversationStatisticsSummary(conversationID: session.id,
                statistics: try summarize(byConversation[session.id] ?? [], configuration: configuration, newWords: newWordsByMessage))
        }
        let byDay = Dictionary(grouping: selected, by: { calendar.startOfDay(for: $0.message.createdAt) })
        let days = try byDay.keys.sorted().map { start in
            guard let day = calendar.dateInterval(of: .day, for: start) else { throw CalculationError.invalidConfiguration }
            return DailyStatisticsSummary(start: day.start, end: day.end,
                statistics: try summarize(byDay[start] ?? [], configuration: configuration, newWords: newWordsByMessage))
        }
        return StatisticsSnapshot(version: StatisticsSnapshot.calculationVersion, computedAt: computedAt,
            configuration: configuration, timeZoneIdentifier: calendar.timeZone.identifier,
            calendarIdentifier: String(describing: calendar.identifier), interval: interval,
            overall: try summarize(selected, configuration: configuration, newWords: newWordsByMessage),
            conversations: conversations, days: days, vocabularyHistory: history)
    }

    /// Sliding frequency map: linear time, without recreating a set per window.
    static func mattr(words: [String], windowSize: Int) throws -> Double? {
        guard windowSize > 0 else { throw CalculationError.invalidConfiguration }
        guard words.count >= windowSize else { return nil }
        var frequencies: [String: Int] = [:]
        for word in words.prefix(windowSize) { frequencies[word, default: 0] += 1 }
        var total = Double(frequencies.count) / Double(windowSize)
        if words.count > windowSize {
            for index in windowSize..<words.count {
                let outgoing = words[index - windowSize]
                let remaining = frequencies[outgoing, default: 0] - 1
                if remaining == 0 { frequencies[outgoing] = nil } else { frequencies[outgoing] = remaining }
                frequencies[words[index], default: 0] += 1
                total += Double(frequencies.count) / Double(windowSize)
            }
        }
        return total / Double(words.count - windowSize + 1)
    }

    private static func summarize(_ attempts: [Attempt], configuration: StatisticsConfiguration,
                                  newWords: [String: Int]) throws -> PracticeStatistics {
        let analyzed = attempts.compactMap(\.text)
        let words = analyzed.flatMap { $0.words.map(\.normalizedForm) }
        let clauseAnalyses = analyzed.filter { $0.clauses != nil }
        var clauses = 0
        for analysis in clauseAnalyses {
            let addition = clauses.addingReportingOverflow(analysis.clauses?.count ?? 0)
            guard !addition.overflow else { throw CalculationError.countOverflow }
            clauses = addition.partialValue
        }
        let grammar = attempts.compactMap(\.grammar)
        let opportunities = grammar.flatMap(\.opportunities)
        let metrics = GrammarObservation.TrackedCategory.allCases.map { category in
            let matching = opportunities.filter { $0.category.categoryID == category.rawValue }
            return GrammarMetricSummary(category: category, correct: matching.filter { $0.outcome == .correct }.count,
                incorrect: matching.filter { $0.outcome == .incorrect }.count,
                uncertain: matching.filter { $0.outcome == .uncertain }.count)
        }
        return PracticeStatistics(practiceAttempts: attempts.count,
            attemptsWithText: attempts.filter { $0.message.statisticsText != nil }.count,
            textAnalyzedAttempts: analyzed.count, grammarEvaluatedAttempts: grammar.count,
            clauseAnalyzedAttempts: clauseAnalyses.count,
            wordCount: analyzed.isEmpty ? nil : words.count,
            sentenceCount: analyzed.isEmpty ? nil : analyzed.reduce(0) { $0 + $1.sentenceSpans.count },
            clauseCount: clauseAnalyses.isEmpty ? nil : clauses,
            sentencesWithClauseAnalysis: clauseAnalyses.reduce(0) { $0 + $1.sentenceSpans.count },
            distinctWordForms: analyzed.isEmpty ? nil : Set(words).count,
            newlyObservedWordForms: analyzed.isEmpty ? nil : attempts.reduce(0) { $0 + (newWords[$1.message.id] ?? 0) },
            mattr: try mattr(words: words, windowSize: configuration.mattrWindowSize), grammar: metrics)
    }
}
