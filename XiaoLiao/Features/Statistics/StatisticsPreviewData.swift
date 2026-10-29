#if DEBUG
import Foundation
import SwiftUI

/// Xcode previews and explicitly isolated UI tests only. These fabricated
/// observations are never seeded into production history or personal stores.
enum StatisticsPreviewData {
    static var sessions: [ConversationSession] { (try? makeSessions()) ?? [] }

    private static func makeSessions() throws -> [ConversationSession] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let topics = ["turtles", "oceans", "forests", "gardens", "birds", "mountains", "rivers", "flowers", "seasons", "islands", "animals", "rain"]
        let provenance = EvaluationProvenance(method: .manual, evaluatorID: "preview-only", evaluatorVersion: "1",
                                              rubricVersion: "sample", taxonomyVersion: "sample")
        var sessions: [ConversationSession] = []
        for day in 0..<12 {
            guard let date = calendar.date(byAdding: .day, value: day - 11, to: today) else { continue }
            let id = "statistics-preview-\(day)"
            if day == 5 {
                // A genuine missing-text case stays a gap when automatic text
                // analysis runs. This placeholder is never played or persisted.
                let audio = Message(id: id + ".message", conversationID: id, createdAt: date.addingTimeInterval(12 * 3600),
                                    senderRole: .user, modality: .spoken,
                                    content: .audio(.init(storageKey: UUID().uuidString + ".caf", durationSeconds: 3)))
                sessions.append(ConversationSession(id: id, title: "预览数据", prompt: "预览数据", messages: [audio], settings: .init()))
                continue
            }
            let sentence = "I enjoy learning about \(topics[day]) because they make our world interesting"
            let sentences = [sentence, "We explore their habitats and discuss how nature changes over time",
                             "My friend enjoys sharing wonderful stories about travel and wildlife",
                             "Although the topic feels difficult I keep practicing with curiosity"]
            let variety = min(4, 1 + day / 3)
            let text = (0..<6).map { sentences[$0 % variety] }.joined(separator: ". ") + "."
            let message = Message(id: id + ".message", conversationID: id, createdAt: date.addingTimeInterval(12 * 3600),
                                  senderRole: .user, modality: .written, content: .text(text))
            guard let analysis = try LocalTextAnalyzer.analyze(message) else { continue }
            var session = ConversationSession(id: id, title: "预览数据", prompt: "预览数据", messages: [message], settings: .init())
            session.textAnalyses = [MessageTextAnalysis(metadata: analysis.metadata,
                normalizationVersion: analysis.normalizationVersion, words: analysis.words, sentenceSpans: analysis.sentenceSpans,
                clauses: .init(count: 9 + day % 4, provenance: provenance))]
            let opportunities = GrammarObservation.TrackedCategory.allCases.enumerated().flatMap { categoryIndex, category in
                (0..<10).map { index in
                    GrammarObservation.Opportunity(id: "\(category.rawValue)-\(index)", category: category.observationCategory,
                        textSpan: analysis.words[(categoryIndex * 10 + index) % analysis.words.count].textSpan,
                        outcome: index < min(9, 4 + day / 3 + categoryIndex % 3) ? .correct : .incorrect,
                        suggestedCorrection: nil, explanation: nil, confidence: nil)
                }
            }
            session.grammarObservations = [GrammarObservation(metadata: .init(id: id + ".grammar", messageID: message.id,
                conversationID: id, messageRevision: 1, textSource: .messageText, evaluatedAt: date,
                provenance: provenance, confidence: nil), opportunities: opportunities)]
            try session.validate()
            sessions.append(session)
        }
        return Array(sessions.reversed())
    }
}

#Preview("全部统计 · 示例数据") {
    StatisticsDashboardView(conversation: ConversationViewModel(history: StatisticsPreviewData.sessions), onBack: {})
        .preferredColorScheme(.light)
}

#Preview("全部统计 · 无分析数据") {
    StatisticsDashboardView(conversation: ConversationViewModel(history: []), onBack: {})
        .preferredColorScheme(.light)
}
#endif
