import Foundation
import XCTest
@testable import XiaoLiao

final class StatisticsDashboardTests: XCTestCase {
    @MainActor
    func testEmptyDashboardHasFiveSelectableCategoriesAndNoInventedValues() throws {
        let model = StatisticsDashboardModel(snapshot: try snapshot([]))
        XCTAssertEqual(model.grammarMetrics.map(\.category), GrammarObservation.TrackedCategory.allCases)
        XCTAssertEqual(model.grammarMetrics.count, 5)
        XCTAssertTrue(model.grammarMetrics.allSatisfy { $0.accuracy == nil })
        XCTAssertTrue(model.grammarTrend.isEmpty)
        XCTAssertTrue(model.vocabularyTrend.isEmpty)
        XCTAssertTrue(model.newVocabulary.isEmpty)
        XCTAssertEqual(model.wordAxisTicks, [0, 1])
        XCTAssertLessThan(model.dateDomain.lowerBound, model.dateDomain.upperBound)
        model.selectedCategory = .tenseConsistency
        XCTAssertEqual(model.selectedMetric?.category, .tenseConsistency)
        XCTAssertNil(model.selectedMetric?.accuracy)
    }

    @MainActor
    func testCategorySelectionChangesTheDailySeriesAndKeepsUnknownDaysAsGaps() throws {
        let model = StatisticsDashboardModel(snapshot: try snapshot([
            session(day: 0, tense: [.correct, .incorrect], articles: [.incorrect]),
            session(day: 1, tense: [.uncertain], articles: [.correct]),
            session(day: 3, tense: [.correct], articles: [.correct, .incorrect])
        ]))
        XCTAssertEqual(model.grammarTrend.map(\.value), [0.5, 1])
        XCTAssertNotEqual(model.grammarTrend[0].segment, model.grammarTrend[1].segment)
        model.selectedCategory = .articles
        XCTAssertEqual(model.grammarTrend.map(\.value), [0, 1, 0.5])
        XCTAssertEqual(model.grammarTrend[0].segment, model.grammarTrend[1].segment)
        XCTAssertNotEqual(model.grammarTrend[1].segment, model.grammarTrend[2].segment)
        XCTAssertEqual(model.selectedMetric?.accuracy, 0.5)
        model.selectedCategory = .subjectVerbAgreement
        XCTAssertTrue(model.grammarTrend.isEmpty)
        XCTAssertNil(model.selectedMetric?.accuracy)
    }

    @MainActor
    func testVocabularyKeepsMeasuredZeroesAndBreaksLinesAcrossMissingDates() throws {
        let model = StatisticsDashboardModel(snapshot: try snapshot([
            session(day: 0, tense: [], articles: []),
            session(day: 1, tense: [], articles: []),
            session(day: 3, tense: [], articles: [])
        ]))
        XCTAssertEqual(model.newVocabulary.map(\.count), [2, 0, 0])
        XCTAssertEqual(model.vocabularyTrend.count, 3)
        XCTAssertEqual(model.vocabularyTrend[0].segment, model.vocabularyTrend[1].segment)
        XCTAssertNotEqual(model.vocabularyTrend[1].segment, model.vocabularyTrend[2].segment)
        XCTAssertEqual(model.dateDomain.lowerBound, model.snapshot?.days.first?.start)
        XCTAssertEqual(model.dateDomain.upperBound, model.snapshot?.days.last?.end)
    }

    @MainActor
    func testLoadFailureCanRetryWithoutResettingCategorySelection() async throws {
        enum Failure: Error { case expected }
        let model = StatisticsDashboardModel()
        model.selectedCategory = .tenseConsistency
        await model.load { throw Failure.expected }
        XCTAssertEqual(model.state, .failed)
        let result = try snapshot([])
        await model.load { result }
        XCTAssertEqual(model.state, .loaded(result))
        XCTAssertEqual(model.selectedCategory, .tenseConsistency)
    }

    @MainActor
    func testOlderAsyncRequestCannotReplaceANewerDashboardSnapshot() async throws {
        let old = try snapshot([])
        let new = try snapshot([session(day: 0, tense: [.correct], articles: [])])
        let model = StatisticsDashboardModel()
        let started = expectation(description: "First load is pending")
        var continuation: CheckedContinuation<StatisticsSnapshot, Never>?
        let first = Task { @MainActor in
            await model.load {
                await withCheckedContinuation { value in continuation = value; started.fulfill() }
            }
        }
        await fulfillment(of: [started], timeout: 2)
        await model.load { new }
        continuation?.resume(returning: old)
        await first.value
        XCTAssertEqual(model.state, .loaded(new))
    }

    @MainActor
    func testUnreadableHistoryDoesNotLookLikeAnEmptyStatisticsResult() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let blocked = directory.appendingPathComponent("occupied")
        try Data("existing data".utf8).write(to: blocked)
        let source = ConversationViewModel.persistent(directory: blocked)
        source.storageIssue = nil // Dismissing the app's alert must not mask the failure.
        do {
            _ = try await source.statisticsSnapshot()
            XCTFail("An unreadable store must not produce an empty dashboard")
        } catch {
            XCTAssertEqual(try Data(contentsOf: blocked), Data("existing data".utf8))
        }
    }

    #if DEBUG
    @MainActor
    func testPreviewCorpusContainsAllFiveMetricsAndActualChartInputs() throws {
        let sessions = StatisticsPreviewData.sessions
        XCTAssertEqual(sessions.count, 12)
        let result = try StatisticsCalculator.snapshot(sessions: sessions)
        XCTAssertEqual(result.overall.grammar.count, 5)
        XCTAssertTrue(result.overall.grammar.allSatisfy { $0.accuracy != nil })
        XCTAssertEqual(result.overall.practiceAttempts, 12)
        XCTAssertEqual(result.overall.textAnalyzedAttempts, 11)
        XCTAssertNotNil(result.overall.clausesPerSentence)
        XCTAssertTrue(result.days.contains { $0.statistics.mattr != nil })
        XCTAssertFalse(result.vocabularyHistory.isEmpty)
    }
    #endif

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func snapshot(_ sessions: [ConversationSession]) throws -> StatisticsSnapshot {
        try StatisticsCalculator.snapshot(sessions: sessions, configuration: .init(mattrWindowSize: 2),
            calendar: calendar, computedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    private func session(day: Int, tense: [GrammarObservation.Outcome], articles: [GrammarObservation.Outcome]) -> ConversationSession {
        let id = "day-\(day)"
        let date = Date(timeIntervalSince1970: 1_699_920_000 + Double(day) * 86_400)
        let message = Message(id: id + ".message", conversationID: id, createdAt: date,
                              senderRole: .user, modality: .written, content: .text("a b a"))
        let provenance = EvaluationProvenance(method: .manual, evaluatorID: "dashboard-test", evaluatorVersion: "1",
                                              rubricVersion: "1", taxonomyVersion: "1")
        func metadata(_ suffix: String) -> ObservationMetadata {
            .init(id: id + suffix, messageID: message.id, conversationID: id, messageRevision: 1,
                  textSource: .messageText, evaluatedAt: date, provenance: provenance, confidence: nil)
        }
        let analysis = MessageTextAnalysis(metadata: metadata(".text"), normalizationVersion: WordForm.version,
            words: [.init(surfaceText: "a", textSpan: .init(startUTF16: 0, lengthUTF16: 1)),
                    .init(surfaceText: "b", textSpan: .init(startUTF16: 2, lengthUTF16: 1)),
                    .init(surfaceText: "a", textSpan: .init(startUTF16: 4, lengthUTF16: 1))],
            sentenceSpans: [.init(startUTF16: 0, lengthUTF16: 5)], clauses: nil)
        let opportunities = [(GrammarObservation.TrackedCategory.verbTense, tense), (.articles, articles)].flatMap { category, outcomes in
            outcomes.enumerated().map { index, outcome in
                GrammarObservation.Opportunity(id: category.rawValue + "-\(index)", category: category.observationCategory,
                    textSpan: .init(startUTF16: 0, lengthUTF16: 1), outcome: outcome,
                    suggestedCorrection: nil, explanation: nil, confidence: nil)
            }
        }
        return ConversationSession(id: id, title: id, prompt: "test", messages: [message], settings: .init(),
            grammarObservations: [.init(metadata: metadata(".grammar"), opportunities: opportunities)], textAnalyses: [analysis])
    }
}
