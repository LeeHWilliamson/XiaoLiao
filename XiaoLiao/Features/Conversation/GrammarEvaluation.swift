import Foundation

nonisolated struct GrammarEvaluationRequest: Codable, Equatable, Sendable {
    static let currentRubricVersion = "grammar-v1"
    static let currentTaxonomyVersion = "grammar-five-v1"
    let requestID: String
    let conversationID: String
    let messageID: String
    let messageRevision: Int
    let textSource: ObservationMetadata.TextSource
    let text: String
    let rubricVersion: String

    init?(message: Message) {
        guard message.countsAsPractice, case .text = message.content,
              let source = message.statisticsText, !source.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              source.text.utf16.count <= 4000, message.revision > 0, message.revision <= 9_007_199_254_740_991,
              UUID(uuidString: message.id) != nil, UUID(uuidString: message.conversationID) != nil else { return nil }
        requestID = UUID().uuidString
        conversationID = message.conversationID
        messageID = message.id
        messageRevision = message.revision
        textSource = source.source
        text = source.text
        rubricVersion = Self.currentRubricVersion
    }

    func matches(_ message: Message) -> Bool {
        UUID(uuidString: requestID) != nil && UUID(uuidString: messageID) != nil && UUID(uuidString: conversationID) != nil
            && messageRevision > 0 && messageRevision <= 9_007_199_254_740_991
            && rubricVersion == Self.currentRubricVersion && text.utf16.count <= 4000
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && message.id == messageID && message.conversationID == conversationID && message.revision == messageRevision
            && message.countsAsPractice && message.statisticsText?.source == textSource
            && message.statisticsText?.text == text
    }
}

nonisolated struct GrammarEvaluationJob: Codable, Equatable, Sendable, Identifiable {
    enum State: String, Codable, Sendable { case queued, attempted, failed }
    let request: GrammarEvaluationRequest
    var state: State = .queued
    var failureMessage: String?
    var id: String { request.requestID }
}

nonisolated struct GrammarEvaluationResponse: Codable, Equatable, Sendable {
    struct Opportunity: Codable, Equatable, Sendable {
        let id: String
        let category: ObservationCategory
        let textSpan: ObservationTextSpan
        let originalText: String
        let outcome: GrammarObservation.Outcome
        let suggestedCorrection: String?
        let explanation: String?
        let confidence: Double?
    }
    let requestID: String
    let conversationID: String
    let messageID: String
    let messageRevision: Int
    let textSource: ObservationMetadata.TextSource
    let rubricVersion: String
    let taxonomyVersion: String
    let model: String
    let evaluatedAtSeconds: Double
    let opportunities: [Opportunity]

    func observation(for request: GrammarEvaluationRequest) throws -> GrammarObservation {
        guard requestID == request.requestID, conversationID == request.conversationID,
              messageID == request.messageID, messageRevision == request.messageRevision, textSource == request.textSource,
              rubricVersion == request.rubricVersion, rubricVersion == GrammarEvaluationRequest.currentRubricVersion,
              taxonomyVersion == GrammarEvaluationRequest.currentTaxonomyVersion,
              !model.isEmpty, model.count <= 200, evaluatedAtSeconds.isFinite, evaluatedAtSeconds > 0,
              evaluatedAtSeconds < 253_402_300_800, opportunities.count <= 128,
              Set(opportunities.map(\.id)).count == opportunities.count else { throw ConversationReplyError.invalidResponse }
        var seen: Set<String> = []
        for item in opportunities {
            guard UUID(uuidString: item.id) != nil,
                  GrammarObservation.TrackedCategory(rawValue: item.category.categoryID) != nil,
                  item.category.subcategoryID.map({ !$0.isEmpty && $0.count <= 80 }) ?? true,
                  let range = item.textSpan.range(in: request.text), !item.originalText.isEmpty,
                  String(request.text[range]) == item.originalText, item.confidence == nil,
                  item.explanation.map({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf16.count <= 800 }) ?? true,
                  seen.insert("\(item.category.categoryID):\(item.textSpan.startUTF16):\(item.textSpan.lengthUTF16)").inserted else {
                throw ConversationReplyError.invalidResponse
            }
            if item.outcome == .incorrect {
                guard let correction = item.suggestedCorrection, !correction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      correction.utf16.count <= 1000, item.explanation != nil else { throw ConversationReplyError.invalidResponse }
            } else if item.suggestedCorrection != nil { throw ConversationReplyError.invalidResponse }
        }
        return GrammarObservation(metadata: .init(id: requestID, messageID: messageID, conversationID: conversationID,
            messageRevision: messageRevision, textSource: textSource, evaluatedAt: Date(timeIntervalSince1970: evaluatedAtSeconds),
            provenance: .init(method: .languageModel, evaluatorID: "xiaoliao-grammar", evaluatorVersion: model,
                              rubricVersion: rubricVersion, taxonomyVersion: taxonomyVersion), confidence: nil),
            opportunities: opportunities.map { .init(id: $0.id, category: $0.category, textSpan: $0.textSpan,
                outcome: $0.outcome, suggestedCorrection: $0.suggestedCorrection, explanation: $0.explanation, confidence: nil) })
    }
}

extension ConversationReplyService {
    func evaluateGrammar(_ request: GrammarEvaluationRequest) async throws -> GrammarEvaluationResponse {
        let response: GrammarEvaluationResponse = try await send(request, path: "v1/grammar/evaluate")
        _ = try response.observation(for: request)
        return response
    }
}
