import Foundation

/// Pure opt-in processing of supplied classifications. Never infers tags, starts
/// an evaluator, edits a session, or persists a result.
nonisolated enum ContextPerformanceCalculator {
    enum ValidationError: Error { case invalidConfiguration, invalidContext, invalidMetadata, duplicateIdentity, unknownMessage }
    static let version = "context-performance-v1"

    static func conversationContext(id: String, conversationID: String, tags: ContextTags,
                                    source: MessageContextAnalysis.Source, recordedAt: Date,
                                    provenance: EvaluationProvenance) throws -> ConversationContext {
        try validate(tags)
        try validate(provenance)
        guard !id.isEmpty, !conversationID.isEmpty, recordedAt.timeIntervalSince1970.isFinite,
              source != .conversationDefault,
              source != .explicitUser || provenance.method == .manual,
              source != .inferred || provenance.method != .manual else { throw ValidationError.invalidContext }
        return ConversationContext(id: id, conversationID: conversationID, recordedAt: recordedAt,
                                   source: source, provenance: provenance, tags: tags)
    }

    static func messageContext(message: Message, metadata: ObservationMetadata, tags: ContextTags,
                               source: MessageContextAnalysis.Source,
                               conversationContext: ConversationContext? = nil) throws -> MessageContextAnalysis {
        try validate(tags)
        try validate(metadata.provenance)
        guard message.countsAsPractice, !message.id.isEmpty, !message.conversationID.isEmpty, message.revision > 0,
              message.createdAt.timeIntervalSince1970.isFinite, let text = message.statisticsText,
              !metadata.id.isEmpty, metadata.messageID == message.id,
              metadata.conversationID == message.conversationID, metadata.messageRevision == message.revision,
              metadata.textSource == text.source, metadata.evaluatedAt.timeIntervalSince1970.isFinite,
              metadata.confidence.map({ $0.isFinite && (0...1).contains($0) }) ?? true,
              source != .explicitUser || metadata.provenance.method == .manual,
              source != .inferred || metadata.provenance.method != .manual else { throw ValidationError.invalidMetadata }
        if source == .conversationDefault {
            guard let parent = conversationContext, parent.conversationID == message.conversationID,
                  parent.tags == tags else { throw ValidationError.invalidContext }
            _ = try self.conversationContext(id: parent.id, conversationID: parent.conversationID, tags: parent.tags,
                source: parent.source, recordedAt: parent.recordedAt, provenance: parent.provenance)
        } else if conversationContext != nil { throw ValidationError.invalidContext }
        return MessageContextAnalysis(metadata: metadata, source: source,
                                      conversationContextID: conversationContext?.id, tags: tags)
    }

    static func summarize(id: String, sessions: [ConversationSession], contexts: [MessageContextAnalysis],
                          conversationContexts: [ConversationContext] = [], skill: ObservationCategory,
                          context: PerformanceContext, interval: DateInterval? = nil,
                          computedAt: Date = Date()) throws -> ContextualPerformanceSummary {
        guard !id.isEmpty, !skill.categoryID.isEmpty, skill.subcategoryID?.isEmpty != true,
              computedAt.timeIntervalSince1970.isFinite,
              interval.map({ $0.start.timeIntervalSince1970.isFinite && $0.end.timeIntervalSince1970.isFinite }) ?? true else {
            throw ValidationError.invalidConfiguration
        }
        guard Set(sessions.map(\.id)).count == sessions.count,
              Set(contexts.map(\.id)).count == contexts.count,
              Set(conversationContexts.map(\.id)).count == conversationContexts.count else {
            throw ValidationError.duplicateIdentity
        }
        var messages: [String: Message] = [:]
        var grammar: [String: GrammarObservation] = [:]
        for session in sessions {
            try session.validate()
            for message in session.messages {
                guard messages.updateValue(message, forKey: message.id) == nil else { throw ValidationError.duplicateIdentity }
            }
            for observation in session.grammarObservations { grammar[observation.metadata.messageID] = observation }
        }
        var parents: [String: ConversationContext] = [:]
        for parent in conversationContexts {
            guard sessions.contains(where: { $0.id == parent.conversationID }) else { throw ValidationError.invalidContext }
            parents[parent.id] = try conversationContext(id: parent.id, conversationID: parent.conversationID,
                tags: parent.tags, source: parent.source, recordedAt: parent.recordedAt, provenance: parent.provenance)
        }
        var byMessage: [String: MessageContextAnalysis] = [:]
        for analysis in contexts {
            guard let message = messages[analysis.metadata.messageID] else { throw ValidationError.unknownMessage }
            let parent = analysis.conversationContextID.flatMap { parents[$0] }
            if analysis.conversationContextID != nil && parent == nil { throw ValidationError.invalidContext }
            let checked = try messageContext(message: message, metadata: analysis.metadata, tags: analysis.tags,
                                             source: analysis.source, conversationContext: parent)
            guard checked == analysis, byMessage.updateValue(analysis, forKey: message.id) == nil else {
                throw ValidationError.duplicateIdentity
            }
        }
        let eligible = messages.values.filter { message in
            message.countsAsPractice && (interval.map { message.createdAt >= $0.start && message.createdAt < $0.end } ?? true)
        }
        let classified = eligible.filter { byMessage[$0.id] != nil }
        let matching = classified.filter { message in
            guard let tags = byMessage[message.id]?.tags else { return false }
            return (context.topic.map { tags.topics.contains($0) } ?? true) &&
                (context.languageTask.map { tags.languageTasks.contains($0) } ?? true) &&
                (context.situation.map { tags.situations.contains($0) } ?? true)
        }.sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt }
        var correct = 0, incorrect = 0, uncertain = 0
        var evidence: [ContextualPerformanceSummary.Evidence] = []
        for message in matching {
            guard let analysis = byMessage[message.id], let observation = grammar[message.id] else { continue }
            let opportunities = observation.opportunities.filter {
                $0.category.categoryID == skill.categoryID &&
                    (skill.subcategoryID == nil || $0.category.subcategoryID == skill.subcategoryID)
            }
            for opportunity in opportunities {
                switch opportunity.outcome {
                case .correct: correct += 1
                case .incorrect: incorrect += 1
                case .uncertain: uncertain += 1
                }
            }
            // An empty opportunity list still proves a completed evaluation.
            evidence.append(.init(conversationID: message.conversationID, messageID: message.id,
                messageRevision: message.revision, logicalMessageID: message.logicalMessageID, submittedAt: message.createdAt,
                contextAnalysisID: analysis.id, grammarObservationID: observation.id, opportunityIDs: opportunities.map(\.id)))
        }
        return ContextualPerformanceSummary(id: id, computedAt: computedAt, calculationVersion: version,
            contextTaxonomyVersion: ContextTaxonomy.version, reportingInterval: interval, context: context, skill: skill,
            correctOpportunities: correct, incorrectOpportunities: incorrect, uncertainOpportunities: uncertain,
            eligiblePracticeAttempts: eligible.count, contextAnalyzedAttempts: classified.count,
            matchingPracticeAttempts: matching.count, grammarEvaluatedAttempts: evidence.count,
            evaluatedConversationCount: Set(evidence.map(\.conversationID)).count,
            evaluatedLogicalMessageCount: Set(evidence.map(\.logicalMessageID)).count,
            firstPracticeAt: matching.first?.createdAt, lastPracticeAt: matching.last?.createdAt, evidence: evidence)
    }

    private static func validate(_ tags: ContextTags) throws {
        func valid<T: Hashable>(_ values: [T], unknown: T) -> Bool {
            !values.isEmpty && Set(values).count == values.count && (!values.contains(unknown) || values.count == 1)
        }
        guard valid(tags.topics, unknown: .unclassified), valid(tags.languageTasks, unknown: .unclassified),
              valid(tags.situations, unknown: .unclassified), (tags.topicDescription?.utf16.count ?? 0) <= 2000 else {
            throw ValidationError.invalidContext
        }
    }

    private static func validate(_ provenance: EvaluationProvenance) throws {
        guard !provenance.evaluatorID.isEmpty, !provenance.evaluatorVersion.isEmpty,
              !provenance.rubricVersion.isEmpty, provenance.taxonomyVersion == ContextTaxonomy.version else {
            throw ValidationError.invalidMetadata
        }
    }
}
