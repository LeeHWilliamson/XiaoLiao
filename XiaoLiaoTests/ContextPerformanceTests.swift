import Foundation
import XCTest
@testable import XiaoLiao

final class ContextPerformanceTests: XCTestCase {
    private var tags: ContextTags {
        .init(topics: [.dailyLife, .workAndCareers], languageTasks: [.recountingPastEvents],
              situations: [.casualConversation], topicDescription: "Talking about yesterday")
    }
    private var provenance: EvaluationProvenance {
        .init(method: .manual, evaluatorID: "test", evaluatorVersion: "1", rubricVersion: "1",
              taxonomyVersion: ContextTaxonomy.version)
    }
    private var filter: PerformanceContext { .init(topic: .dailyLife, languageTask: .recountingPastEvents, situation: nil) }
    private var skill: ObservationCategory { GrammarObservation.TrackedCategory.verbTense.observationCategory }
    private func message(_ id: String = "original") -> Message {
        Message(id: id, conversationID: "conversation", createdAt: Date(timeIntervalSince1970: 100),
                senderRole: .user, modality: .written, content: .text("I go."))
    }
    private func metadata(_ message: Message) -> ObservationMetadata {
        .init(id: "context-" + message.id, messageID: message.id, conversationID: message.conversationID,
              messageRevision: message.revision, textSource: .messageText,
              evaluatedAt: Date(timeIntervalSince1970: 200), provenance: provenance, confidence: nil)
    }
    private func classify(_ message: Message, tags: ContextTags? = nil) throws -> MessageContextAnalysis {
        try ContextPerformanceCalculator.messageContext(message: message, metadata: metadata(message),
            tags: tags ?? self.tags, source: .explicitUser)
    }
    private func session(_ messages: [Message], outcomes: [GrammarObservation.Outcome?]) -> ConversationSession {
        let observations = zip(messages, outcomes).compactMap { message, outcome -> GrammarObservation? in
            guard let outcome else { return nil }
            return GrammarObservation(metadata: metadata(message), opportunities: [
                .init(id: "opportunity-" + message.id, category: skill,
                      textSpan: .init(startUTF16: 2, lengthUTF16: 2), outcome: outcome,
                      suggestedCorrection: nil, explanation: nil, confidence: nil)
            ])
        }
        return ConversationSession(id: "conversation", title: "Test", prompt: "Practice", messages: messages,
                                   settings: .init(), grammarObservations: observations)
    }

    func testFactoriesRoundTripAndValidateConversationDefaultLinks() throws {
        let message = message()
        let parent = try ContextPerformanceCalculator.conversationContext(id: "parent", conversationID: message.conversationID,
            tags: tags, source: .explicitUser, recordedAt: Date(), provenance: provenance)
        let analysis = try ContextPerformanceCalculator.messageContext(message: message, metadata: metadata(message),
            tags: tags, source: .conversationDefault, conversationContext: parent)
        XCTAssertEqual(analysis.conversationContextID, parent.id)
        XCTAssertEqual(try JSONDecoder().decode(MessageContextAnalysis.self, from: JSONEncoder().encode(analysis)), analysis)
        XCTAssertThrowsError(try ContextPerformanceCalculator.messageContext(message: message, metadata: metadata(message),
            tags: tags, source: .conversationDefault))
        XCTAssertThrowsError(try ContextPerformanceCalculator.messageContext(message: message, metadata: metadata(message),
            tags: tags, source: .explicitUser, conversationContext: parent))
        let summary = try ContextPerformanceCalculator.summarize(id: "report", sessions: [session([message], outcomes: [.correct])],
            contexts: [analysis], conversationContexts: [parent], skill: skill, context: filter)
        XCTAssertEqual(summary.correctOpportunities, 1)
        XCTAssertEqual(try JSONDecoder().decode(ContextualPerformanceSummary.self, from: JSONEncoder().encode(summary)), summary)
    }

    func testInvalidTagsExactVersionAndConfidenceAreRejected() throws {
        let message = message()
        for invalid in [
            ContextTags(topics: [], languageTasks: [.describing], situations: [.interview], topicDescription: nil),
            ContextTags(topics: [.dailyLife, .dailyLife], languageTasks: [.describing], situations: [.interview], topicDescription: nil),
            ContextTags(topics: [.unclassified, .dailyLife], languageTasks: [.describing], situations: [.interview], topicDescription: nil)
        ] { XCTAssertThrowsError(try classify(message, tags: invalid)) }
        XCTAssertThrowsError(try ContextPerformanceCalculator.messageContext(message: message.edited(content: .text("I go.")),
            metadata: metadata(message), tags: tags, source: .explicitUser))
        let invalid = ObservationMetadata(id: "bad", messageID: message.id, conversationID: message.conversationID,
            messageRevision: 1, textSource: .messageText, evaluatedAt: Date(), provenance: provenance, confidence: .nan)
        XCTAssertThrowsError(try ContextPerformanceCalculator.messageContext(message: message, metadata: invalid, tags: tags, source: .inferred))
    }

    func testEditsCountFullyButLogicalDiversityAndUncertainDenominatorRemainDistinct() throws {
        let original = message()
        let edit = original.edited(content: .text("I go."))
        let uncertain = message("uncertain")
        let value = session([original, edit, uncertain], outcomes: [.correct, .incorrect, .uncertain])
        let report = try ContextPerformanceCalculator.summarize(id: "report", sessions: [value],
            contexts: try [original, edit, uncertain].map { try classify($0) }, skill: skill, context: filter)
        XCTAssertEqual(report.matchingPracticeAttempts, 3)
        XCTAssertEqual(report.grammarEvaluatedAttempts, 3)
        XCTAssertEqual(report.evaluatedLogicalMessageCount, 2)
        XCTAssertEqual(report.evaluatedConversationCount, 1)
        XCTAssertEqual(report.correctOpportunities, 1)
        XCTAssertEqual(report.incorrectOpportunities, 1)
        XCTAssertEqual(report.uncertainOpportunities, 1)
        XCTAssertEqual(report.accuracy, 0.5)
        XCTAssertEqual(Set(report.evidence.map(\.messageID)), Set([original.id, edit.id, uncertain.id]))
    }

    func testCoverageMissingContextEmptyEvaluationAndUnknownAreNotSyntheticSuccesses() throws {
        let known = message("known"), unknown = message("unknown"), missing = message("missing")
        var value = session([known, unknown, missing], outcomes: [nil, nil, nil])
        value.grammarObservations = [.init(metadata: metadata(known), opportunities: [])]
        let unknownTags = ContextTags(topics: [.unclassified], languageTasks: [.unclassified], situations: [.unclassified], topicDescription: nil)
        let contexts = try [classify(known), classify(unknown, tags: unknownTags)]
        let baseline = try ContextPerformanceCalculator.summarize(id: "baseline", sessions: [value], contexts: contexts,
            skill: skill, context: .init(topic: nil, languageTask: nil, situation: nil))
        XCTAssertEqual(baseline.eligiblePracticeAttempts, 3)
        XCTAssertEqual(baseline.contextAnalyzedAttempts, 2)
        XCTAssertEqual(baseline.matchingPracticeAttempts, 2)
        XCTAssertEqual(baseline.grammarEvaluatedAttempts, 1)
        XCTAssertEqual(baseline.evidence.first?.opportunityIDs, [])
        XCTAssertNil(baseline.accuracy)
        let unknownOnly = try ContextPerformanceCalculator.summarize(id: "unknown", sessions: [value], contexts: contexts,
            skill: skill, context: .init(topic: .unclassified, languageTask: nil, situation: nil))
        XCTAssertEqual(unknownOnly.matchingPracticeAttempts, 1)
        XCTAssertEqual(unknownOnly.grammarEvaluatedAttempts, 0)
    }

    func testMissingDataAndNonPracticeContentNeverCreateEvaluations() throws {
        let learner = message()
        let fixture = Message(id: "fixture", conversationID: learner.conversationID, senderRole: .user,
                              modality: .written, content: .text("I go."), origin: .fixture)
        let partner = Message(id: "partner", conversationID: learner.conversationID, senderRole: .aiPartner,
                              modality: .written, content: .text("I go."))
        let value = session([learner, fixture, partner], outcomes: [nil, nil, nil])
        let report = try ContextPerformanceCalculator.summarize(id: "empty", sessions: [value], contexts: [],
            skill: skill, context: filter)
        XCTAssertEqual(report.eligiblePracticeAttempts, 1)
        XCTAssertEqual(report.contextAnalyzedAttempts, 0)
        XCTAssertEqual(report.matchingPracticeAttempts, 0)
        XCTAssertTrue(report.evidence.isEmpty)
        XCTAssertNil(report.accuracy)
        XCTAssertThrowsError(try classify(fixture))
        XCTAssertThrowsError(try classify(partner))
    }

    func testUnknownTaxonomyAndWrongTextSourceAreRejected() throws {
        let message = message()
        let old = EvaluationProvenance(method: .manual, evaluatorID: "test", evaluatorVersion: "1",
                                       rubricVersion: "1", taxonomyVersion: "unknown")
        XCTAssertThrowsError(try ContextPerformanceCalculator.conversationContext(id: "old", conversationID: message.conversationID,
            tags: tags, source: .explicitUser, recordedAt: Date(), provenance: old))
        let wrongSource = ObservationMetadata(id: "wrong", messageID: message.id, conversationID: message.conversationID,
            messageRevision: message.revision, textSource: .speechTranscription, evaluatedAt: Date(), provenance: provenance, confidence: nil)
        XCTAssertThrowsError(try ContextPerformanceCalculator.messageContext(message: message, metadata: wrongSource,
            tags: tags, source: .explicitUser))
    }

    func testHalfOpenIntervalsAndDuplicateOrOrphanedClassifications() throws {
        let original = message(), edit = message().edited(content: .text("I go."))
        let value = session([original, edit], outcomes: [.correct, .incorrect])
        let contexts = try [classify(original), classify(edit)]
        let report = try ContextPerformanceCalculator.summarize(id: "filtered", sessions: [value], contexts: contexts,
            skill: skill, context: filter, interval: DateInterval(start: original.createdAt, end: edit.createdAt))
        XCTAssertEqual(report.matchingPracticeAttempts, 1)
        XCTAssertEqual(report.correctOpportunities, 1)
        XCTAssertThrowsError(try ContextPerformanceCalculator.summarize(id: "duplicate", sessions: [value],
            contexts: contexts + [contexts[0]], skill: skill, context: filter))
        XCTAssertThrowsError(try ContextPerformanceCalculator.summarize(id: "orphan", sessions: [value],
            contexts: [classify(message("absent"))], skill: skill, context: filter))
    }
}
