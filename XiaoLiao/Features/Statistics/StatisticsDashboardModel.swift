import Foundation
import Observation

@MainActor
@Observable
final class StatisticsDashboardModel {
    enum State: Equatable {
        case loading
        case loaded(StatisticsSnapshot)
        case failed
    }

    private(set) var state: State
    var selectedCategory: GrammarObservation.TrackedCategory = .verbTense
    @ObservationIgnored private var requestID = UUID()

    init(snapshot: StatisticsSnapshot? = nil) {
        state = snapshot.map(State.loaded) ?? .loading
    }

    var snapshot: StatisticsSnapshot? {
        guard case let .loaded(value) = state else { return nil }
        return value
    }

    func load(using operation: @MainActor () async throws -> StatisticsSnapshot) async {
        let request = UUID()
        requestID = request
        state = .loading
        do {
            let result = try await operation()
            guard !Task.isCancelled, requestID == request else { return }
            state = .loaded(result)
        } catch {
            guard !Task.isCancelled, requestID == request else { return }
            state = .failed
        }
    }

    var grammarMetrics: [GrammarMetricSummary] {
        GrammarObservation.TrackedCategory.allCases.map { category in
            snapshot?.overall.grammar.first { $0.category == category }
                ?? .init(category: category, correct: 0, incorrect: 0, uncertain: 0)
        }
    }

    var selectedMetric: GrammarMetricSummary? { grammarMetrics.first { $0.category == selectedCategory } }

    var grammarTrend: [StatisticsTrendPoint] {
        trend { day in day.statistics.grammar.first { $0.category == selectedCategory }?.accuracy }
    }

    var vocabularyTrend: [StatisticsTrendPoint] { trend { $0.statistics.mattr } }

    var newVocabulary: [StatisticsVocabularyPoint] {
        snapshot?.days.compactMap { day in
            day.statistics.newlyObservedWordForms.map { StatisticsVocabularyPoint(date: day.start, count: $0) }
        } ?? []
    }

    var dateDomain: ClosedRange<Date> {
        if let first = snapshot?.days.first, let last = snapshot?.days.last { return first.start...last.end }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = snapshot.flatMap { TimeZone(identifier: $0.timeZoneIdentifier) } ?? .current
        let start = calendar.startOfDay(for: snapshot?.computedAt ?? Date())
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return start...end
    }

    var wordAxisTicks: [Int] {
        let maximum = newVocabulary.map(\.count).max() ?? 0
        if maximum <= 1 { return [0, 1] }
        let step = max(1, Int(ceil(Double(maximum) / 4)))
        return (0...4).map { $0 * step }
    }

    /// A new segment prevents a line joining across missing/unevaluated days.
    private func trend(value: (DailyStatisticsSummary) -> Double?) -> [StatisticsTrendPoint] {
        var points: [StatisticsTrendPoint] = []
        var previousEnd: Date?
        var segment = 0
        for day in snapshot?.days ?? [] {
            guard let score = value(day) else { previousEnd = nil; segment += 1; continue }
            if let previousEnd, previousEnd != day.start { segment += 1 }
            points.append(.init(date: day.start, value: score, segment: segment))
            previousEnd = day.end
        }
        return points
    }
}

nonisolated struct StatisticsTrendPoint: Identifiable, Equatable {
    let date: Date
    let value: Double
    let segment: Int
    var id: Date { date }
}

nonisolated struct StatisticsVocabularyPoint: Identifiable, Equatable {
    let date: Date
    let count: Int
    var id: Date { date }
}

extension GrammarObservation.TrackedCategory {
    var title: String {
        switch self {
        case .verbTense: "动词时态"
        case .tenseConsistency: "时态一致性"
        case .articles: "冠词"
        case .prepositions: "介词"
        case .subjectVerbAgreement: "主谓一致"
        }
    }
}
