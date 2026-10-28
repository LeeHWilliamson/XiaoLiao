import Foundation
import XCTest
@testable import XiaoLiao

final class StatisticsTests: XCTestCase {
    func testMATTRUsesEverySlidingWindowAndRequiresEnoughWords() throws {
        XCTAssertEqual(try XCTUnwrap(StatisticsCalculator.mattr(words: ["a", "a", "b", "c"], windowSize: 3)), 5.0 / 6.0, accuracy: 0.000001)
        XCTAssertEqual(try StatisticsCalculator.mattr(words: ["a", "a", "a"], windowSize: 3), 1.0 / 3.0)
        XCTAssertEqual(try StatisticsCalculator.mattr(words: ["a", "b"], windowSize: 1), 1)
        XCTAssertNil(try StatisticsCalculator.mattr(words: ["a"], windowSize: 2))
        XCTAssertNil(try StatisticsCalculator.mattr(words: [], windowSize: 1))
        XCTAssertThrowsError(try StatisticsCalculator.mattr(words: ["a"], windowSize: 0))
        XCTAssertThrowsError(try StatisticsCalculator.snapshot(sessions: [], configuration: .init(mattrWindowSize: -1)))
    }

    func testEditsFullyCountWhileFixturesSystemPartnerAndUnsentMessagesDoNot() throws {
        let original = message("original", text: "Run runs running Run", time: 0)
        let edit = Message(id: "edit", logicalMessageID: original.id, replacesMessageID: original.id,
                           conversationID: "one", createdAt: date(10), senderRole: .user, modality: .written,
                           content: .text("Run runs running Run"), revision: 2)
        let excluded = [message("demo", text: "fixture", origin: .fixture),
                        message("partner", text: "partner", role: .aiPartner),
                        message("request", text: "system", purpose: .systemAssistance),
                        message("system", text: "system", role: .system, purpose: .systemAssistance),
                        message("failed", text: "failed", status: .failed),
                        message("pending", text: "pending", status: .pending),
                        message("unknown", text: "unknown", origin: nil)]
        let value = try session(messages: [original, edit] + excluded, analyzed: [original, edit])
        let snapshot = try report([value])
        XCTAssertEqual(snapshot.overall.practiceAttempts, 2)
        XCTAssertEqual(snapshot.overall.wordCount, 8)
        XCTAssertEqual(snapshot.overall.sentenceCount, 2)
        XCTAssertEqual(snapshot.overall.distinctWordForms, 3)
        XCTAssertEqual(snapshot.vocabularyHistory.map(\.wordForm).sorted(), ["run", "running", "runs"])
        XCTAssertTrue(snapshot.vocabularyHistory.allSatisfy { $0.firstMessageID == original.id })
        XCTAssertEqual(snapshot, try report([value]))
        XCTAssertEqual(try JSONDecoder().decode(StatisticsSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
    }

    func testEditingADemoBecomesARealPracticeAttempt() {
        let demo = message("demo", text: "hello", origin: .fixture)
        let edit = demo.edited(content: .text("hello again"))
        XCTAssertFalse(demo.countsAsPractice)
        XCTAssertTrue(edit.countsAsPractice)
        XCTAssertEqual(edit.origin, .interaction)
        XCTAssertEqual(edit.replacesMessageID, demo.id)
    }

    func testGrammarRatesUseTrackedOpportunitiesAndExcludeUncertainDenominators() throws {
        let first = message("first", text: "hello")
        let second = message("second", text: "again", time: 10)
        let categories: [(String, GrammarObservation.Outcome)] = [
            ("verb-tense", .correct), ("verb-tense", .incorrect), ("verb-tense", .uncertain),
            ("article-usage", .correct), ("preposition-usage", .uncertain), ("future-category", .incorrect),
            ("tense-consistency", .correct), ("tense-consistency", .incorrect)
        ]
        var value = try session(messages: [first, second], analyzed: [])
        value.grammarObservations = [
            GrammarObservation(metadata: metadata(first), opportunities: categories.enumerated().map { index, entry in
                .init(id: "rule-\(index)", category: .init(categoryID: entry.0, subcategoryID: "sub-\(index)"),
                      textSpan: .init(startUTF16: 0, lengthUTF16: 1), outcome: entry.1,
                      suggestedCorrection: nil, explanation: nil, confidence: nil)
            }),
            GrammarObservation(metadata: metadata(second), opportunities: [])
        ]
        let summary = try report([value]).overall
        XCTAssertEqual(summary.grammarEvaluatedAttempts, 2)
        XCTAssertEqual(summary.grammar.count, 5)
        let tense = try XCTUnwrap(summary.grammar.first { $0.category == .verbTense })
        XCTAssertEqual(tense.accuracy, 0.5)
        XCTAssertEqual(tense.uncertain, 1)
        XCTAssertEqual(summary.grammar.first { $0.category == .articles }?.accuracy, 1)
        XCTAssertEqual(summary.grammar.first { $0.category == .tenseConsistency }?.accuracy, 0.5)
        XCTAssertNil(summary.grammar.first { $0.category == .prepositions }?.accuracy)
        XCTAssertNil(summary.grammar.first { $0.category == .subjectVerbAgreement }?.accuracy)
    }

    func testPartialCoverageDoesNotTurnUnknownAnalysisIntoZeroOrMismatchedRatios() throws {
        let first = message("first", text: "a b")
        let second = message("second", text: "c d e", time: 10)
        let noAnalysis = message("not-yet", text: "more", time: 20)
        let audio = Message(id: "audio", conversationID: "one", createdAt: date(30), senderRole: .user,
                            modality: .spoken, content: .audio(.init(storageKey: UUID().uuidString + ".caf", durationSeconds: 2)))
        var value = try session(messages: [first, second, noAnalysis, audio], analyzed: [])
        value.textAnalyses = [try analysis(first, sentences: [.init(startUTF16: 0, lengthUTF16: 1), .init(startUTF16: 2, lengthUTF16: 1)], clauses: 3),
                              try analysis(second, sentences: [.init(startUTF16: 0, lengthUTF16: 1), .init(startUTF16: 2, lengthUTF16: 1),
                                                               .init(startUTF16: 4, lengthUTF16: 1)])]
        let summary = try report([value]).overall
        XCTAssertEqual(summary.practiceAttempts, 4)
        XCTAssertEqual(summary.attemptsWithText, 3)
        XCTAssertEqual(summary.textAnalyzedAttempts, 2)
        XCTAssertEqual(summary.clauseAnalyzedAttempts, 1)
        XCTAssertEqual(summary.sentenceCount, 5)
        XCTAssertEqual(summary.clauseCount, 3)
        XCTAssertEqual(summary.clausesPerSentence, 1.5)
        let unknown = try report([session(messages: [noAnalysis], analyzed: [])]).overall
        XCTAssertNil(unknown.wordCount)
        XCTAssertNil(unknown.sentenceCount)
        XCTAssertNil(unknown.clauseCount)
        XCTAssertNil(unknown.clausesPerSentence)
        XCTAssertNil(unknown.mattr)
        XCTAssertNil(unknown.newlyObservedWordForms)
        XCTAssertTrue(unknown.grammar.allSatisfy { $0.accuracy == nil })
    }

    func testGrammarEvaluationsOfOriginalAndEditBothContribute() throws {
        let original = message("original", text: "hello")
        let edit = original.edited(content: .text("again"))
        var value = try session(messages: [original, edit], analyzed: [])
        value.grammarObservations = zip([original, edit], [GrammarObservation.Outcome.incorrect, .correct]).map { record, outcome in
            GrammarObservation(metadata: metadata(record), opportunities: [
                .init(id: UUID().uuidString, category: GrammarObservation.TrackedCategory.verbTense.observationCategory,
                      textSpan: .init(startUTF16: 0, lengthUTF16: 1), outcome: outcome,
                      suggestedCorrection: nil, explanation: nil, confidence: nil)
            ])
        }
        let summary = try report([value]).overall
        XCTAssertEqual(summary.practiceAttempts, 2)
        XCTAssertEqual(summary.grammarEvaluatedAttempts, 2)
        XCTAssertEqual(summary.grammar.first { $0.category == .verbTense }?.accuracy, 0.5)
    }

    func testExplicitEmptyAndZeroResultsRemainDistinctFromMissingAnalysis() throws {
        let punctuation = message("punctuation", text: "...")
        var value = try session(messages: [punctuation], analyzed: [])
        value.textAnalyses = [MessageTextAnalysis(metadata: metadata(punctuation), normalizationVersion: WordForm.version,
            words: [], sentenceSpans: [], clauses: .init(count: 0, provenance: provenance))]
        let summary = try report([value]).overall
        XCTAssertEqual(summary.textAnalyzedAttempts, 1)
        XCTAssertEqual(summary.wordCount, 0)
        XCTAssertEqual(summary.sentenceCount, 0)
        XCTAssertEqual(summary.clauseCount, 0)
        XCTAssertNil(summary.clausesPerSentence)
        XCTAssertNil(summary.mattr)
    }

    func testFirstUseUsesAllHistoryAndSubmissionDatesBeforeFilteringThePeriod() throws {
        let older = message("older", text: "Run", conversation: "old", time: 0)
        let recent = message("recent", text: "run runs running", conversation: "new", time: 86_400)
        let end = message("at-end", text: "excluded", conversation: "new", time: 172_800)
        let sessions = try [session(messages: [recent, end], analyzed: [recent, end]), session(messages: [older], analyzed: [older])]
        let snapshot = try StatisticsCalculator.snapshot(sessions: sessions, configuration: .init(mattrWindowSize: 2),
            interval: DateInterval(start: date(86_400), end: date(172_800)), calendar: calendar, computedAt: date(999_999))
        XCTAssertEqual(snapshot.overall.practiceAttempts, 1)
        XCTAssertEqual(snapshot.overall.newlyObservedWordForms, 2)
        let run = try XCTUnwrap(snapshot.vocabularyHistory.first { $0.wordForm == "run" })
        XCTAssertEqual(run.firstMessageID, older.id)
        XCTAssertEqual(run.firstUsedAt, older.createdAt)
        XCTAssertEqual(snapshot.days.count, 1)
        XCTAssertEqual(snapshot.days[0].start, calendar.startOfDay(for: recent.createdAt))
        XCTAssertEqual(snapshot.conversations.first { $0.conversationID == "old" }?.statistics.practiceAttempts, 0)
    }

    func testOverallDiversityIsComputedFromTheWordStreamRatherThanAveragedScores() throws {
        let a = message("a", text: "a a a", conversation: "one", time: 0)
        let b = message("b", text: "b b b", conversation: "two", time: 86_400)
        let snapshot = try report([session(messages: [b], analyzed: [b]), session(messages: [a], analyzed: [a])])
        XCTAssertEqual(try XCTUnwrap(snapshot.overall.mattr), 0.6, accuracy: 0.000001)
        XCTAssertTrue(snapshot.conversations.allSatisfy { $0.statistics.mattr == 0.5 })
        XCTAssertEqual(snapshot.days.count, 2)
        XCTAssertEqual(snapshot.days.reduce(0) { $0 + ($1.statistics.newlyObservedWordForms ?? 0) }, 2)
    }

    func testLocalExtractionCountsWordFormsAndSentencesWithoutInventingClauseOrGrammarResults() throws {
        let input = message("input", text: "Run runs running. RUN!")
        let result = try XCTUnwrap(LocalTextAnalyzer.analyze(input))
        XCTAssertEqual(result.words.map(\.normalizedForm), ["run", "runs", "running", "run"])
        XCTAssertEqual(result.sentenceSpans.count, 2)
        XCTAssertNil(result.clauses)
        XCTAssertEqual(result.metadata.textSource, .messageText)
        XCTAssertNil(try LocalTextAnalyzer.analyze(message("demo", text: "demo", origin: .fixture)))
        let audio = Message(conversationID: "one", senderRole: .user, modality: .spoken,
                            content: .audio(.init(storageKey: UUID().uuidString + ".caf", durationSeconds: 2)))
        XCTAssertNil(try LocalTextAnalyzer.analyze(audio))
        let spoken = Message(conversationID: "one", senderRole: .user, modality: .spoken, content: .text("ignored"),
                             transcription: .init(text: "I like turtles.", confidence: nil))
        XCTAssertEqual(try LocalTextAnalyzer.analyze(spoken)?.metadata.textSource, .speechTranscription)
        XCTAssertEqual(try LocalTextAnalyzer.analyze(spoken)?.words.map(\.normalizedForm), ["i", "like", "turtles"])
        XCTAssertFalse(WordForm.isWord("123"))
        XCTAssertFalse(WordForm.isWord("中文"))
        XCTAssertEqual(WordForm.normalize("DON’T"), "don't")
    }

    func testInvalidAnalysisAndDuplicateIdentitiesAreRejected() throws {
        let input = message("input", text: "hello")
        var value = try session(messages: [input], analyzed: [])
        value.textAnalyses = [MessageTextAnalysis(metadata: metadata(input), normalizationVersion: WordForm.version,
            words: [.init(surfaceText: "stale", textSpan: .init(startUTF16: 0, lengthUTF16: 5))],
            sentenceSpans: [.init(startUTF16: 0, lengthUTF16: 5)], clauses: nil)]
        XCTAssertThrowsError(try report([value]))
        value.textAnalyses = [try analysis(input, clauses: -1)]
        XCTAssertThrowsError(try report([value]))
        value.textAnalyses = [try analysis(input)]
        XCTAssertThrowsError(try report([value, value]))
        value.textAnalyses.append(try analysis(input))
        XCTAssertThrowsError(try report([value]))
    }

    @MainActor
    func testAnalysisPersistsPerVersionAndFailedWritesDoNotChangeResults() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = ConversationViewModel.persistent(directory: directory)
        model.suggestPrompt()
        XCTAssertTrue(model.startConversation())
        let id = try XCTUnwrap(model.activeSessionID)
        model.draft = "Run runs running."
        XCTAssertTrue(model.submitDraft())
        let original = try XCTUnwrap(model.messages.last)
        XCTAssertTrue(model.recordTextAnalysis(try XCTUnwrap(LocalTextAnalyzer.analyze(original))))
        model.selectMessage(original.id)
        model.perform(.edit, on: original.id)
        model.draft = "Run runs running again."
        XCTAssertTrue(model.submitDraft())
        let edit = try XCTUnwrap(model.messages.last)
        XCTAssertEqual(model.textAnalyses.count, 1)
        let editAnalysis = try XCTUnwrap(LocalTextAnalyzer.analyze(edit))
        XCTAssertTrue(model.recordTextAnalysis(editAnalysis))
        let reevaluated = try XCTUnwrap(LocalTextAnalyzer.analyze(edit))
        XCTAssertTrue(model.recordTextAnalysis(reevaluated))
        XCTAssertEqual(model.textAnalyses.count, 2)
        XCTAssertFalse(model.textAnalyses.contains { $0.id == editAnalysis.id })
        let relaunched = ConversationViewModel.persistent(directory: directory)
        XCTAssertTrue(relaunched.openConversation(id))
        XCTAssertEqual(relaunched.textAnalyses, model.textAnalyses)
        let summary = try await relaunched.statisticsSnapshot(configuration: .init(mattrWindowSize: 2))
        XCTAssertEqual(summary.overall.practiceAttempts, 2)
        XCTAssertEqual(summary.overall.wordCount, 7)
        XCTAssertEqual(summary.overall.sentenceCount, 2)
        XCTAssertEqual(summary.vocabularyHistory.count, 4)
        let readOnly = ConversationViewModel.persistent(store: try ConversationHistoryStore(directory: directory, allowsSave: false))
        XCTAssertTrue(readOnly.openConversation(id))
        let before = readOnly.textAnalyses
        XCTAssertFalse(readOnly.recordTextAnalysis(editAnalysis))
        XCTAssertEqual(readOnly.textAnalyses, before)
        XCTAssertTrue(readOnly.openConversation(id))
        XCTAssertEqual(readOnly.textAnalyses, before)
    }

    func testOlderPayloadDecodesWithoutResetAndUnknownOriginsStayOutOfStatistics() throws {
        let original = message("legacy", text: "hello")
        let value = try session(messages: [original], analyzed: [])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        json["textAnalyses"] = nil
        var messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        messages[0]["origin"] = nil
        json["messages"] = messages
        let decoded = try JSONDecoder().decode(ConversationSession.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.messages[0].content, original.content)
        XCTAssertNil(decoded.messages[0].origin)
        XCTAssertTrue(decoded.textAnalyses.isEmpty)
        XCTAssertEqual(try report([decoded]).overall.practiceAttempts, 0)
    }

    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }
    private func date(_ offset: TimeInterval) -> Date { Date(timeIntervalSince1970: 1_700_000_000 + offset) }
    private var provenance: EvaluationProvenance {
        .init(method: .manual, evaluatorID: "statistics-test", evaluatorVersion: "1", rubricVersion: "1", taxonomyVersion: "1")
    }
    private func message(_ id: String, text: String, conversation: String = "one", time: TimeInterval = 0,
                         role: Message.SenderRole = .user, purpose: Message.Purpose = .conversationPractice,
                         status: Message.Status? = .complete, origin: Message.Origin? = .interaction) -> Message {
        Message(id: id, conversationID: conversation, createdAt: date(time), senderRole: role,
                purpose: purpose, modality: .written, content: .text(text), status: status, origin: origin)
    }
    private func metadata(_ message: Message) -> ObservationMetadata {
        .init(id: UUID().uuidString, messageID: message.id, conversationID: message.conversationID,
              messageRevision: message.revision, textSource: .messageText, evaluatedAt: date(999_999),
              provenance: provenance, confidence: nil)
    }
    private func analysis(_ message: Message, sentences: [ObservationTextSpan]? = nil, clauses: Int? = nil) throws -> MessageTextAnalysis {
        guard case let .text(text) = message.content else { throw NSError(domain: "TestFixture", code: 1) }
        var search = text.startIndex
        let words = try text.split(separator: " ").map { token -> MessageTextAnalysis.Word in
            let range = try XCTUnwrap(text.range(of: String(token), range: search..<text.endIndex))
            search = range.upperBound
            let span = NSRange(range, in: text)
            return .init(surfaceText: String(token), textSpan: .init(startUTF16: span.location, lengthUTF16: span.length))
        }
        return MessageTextAnalysis(metadata: metadata(message), normalizationVersion: WordForm.version, words: words,
            sentenceSpans: sentences ?? [.init(startUTF16: 0, lengthUTF16: text.utf16.count)],
            clauses: clauses.map { .init(count: $0, provenance: provenance) })
    }
    private func session(messages: [Message], analyzed: [Message]) throws -> ConversationSession {
        ConversationSession(id: messages.first?.conversationID ?? "one", title: "test", prompt: "test", messages: messages,
                            settings: .init(), textAnalyses: try analyzed.map { try analysis($0) })
    }
    private func report(_ sessions: [ConversationSession]) throws -> StatisticsSnapshot {
        try StatisticsCalculator.snapshot(sessions: sessions, configuration: .init(mattrWindowSize: 2),
                                          calendar: calendar, computedAt: date(999_999))
    }
}
