import Foundation

nonisolated struct ConversationSession: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let title: String
    let prompt: String
    /// Append-only originals and edits, including superseded versions.
    var messages: [Message]
    var settings: ConversationSettings
    var grammarObservations: [GrammarObservation] = []
    var vocabularyObservations: [VocabularyObservation] = []
    var textAnalyses: [MessageTextAnalysis] = []
    var pendingReply: PendingConversationReply?

    init(id: String, title: String, prompt: String, messages: [Message], settings: ConversationSettings,
         grammarObservations: [GrammarObservation] = [], vocabularyObservations: [VocabularyObservation] = [],
         textAnalyses: [MessageTextAnalysis] = [], pendingReply: PendingConversationReply? = nil) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.messages = messages
        self.settings = settings
        self.grammarObservations = grammarObservations
        self.vocabularyObservations = vocabularyObservations
        self.textAnalyses = textAnalyses
        self.pendingReply = pendingReply
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, prompt, messages, settings, grammarObservations, vocabularyObservations, textAnalyses, pendingReply
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        prompt = try values.decode(String.self, forKey: .prompt)
        messages = try values.decode([Message].self, forKey: .messages)
        settings = try values.decode(ConversationSettings.self, forKey: .settings)
        grammarObservations = try values.decode([GrammarObservation].self, forKey: .grammarObservations)
        vocabularyObservations = try values.decode([VocabularyObservation].self, forKey: .vocabularyObservations)
        textAnalyses = try values.decodeIfPresent([MessageTextAnalysis].self, forKey: .textAnalyses) ?? []
        pendingReply = try values.decodeIfPresent(PendingConversationReply.self, forKey: .pendingReply)
    }

    var latestMessages: [Message] { Self.latestVersions(in: messages) }

    /// Keep each logical message in its first position while displaying its newest version.
    static func latestVersions(in records: [Message]) -> [Message] {
        var positions: [String: Int] = [:]
        var latest: [Message] = []
        for record in records {
            if let index = positions[record.logicalMessageID] {
                if record.revision > latest[index].revision { latest[index] = record }
            } else {
                positions[record.logicalMessageID] = latest.count
                latest.append(record)
            }
        }
        return latest
    }

    enum ValidationError: Error { case invalidMessage, invalidEditChain, invalidObservation }

    func validate() throws {
        guard !id.isEmpty else { throw ValidationError.invalidMessage }
        var records: [String: Message] = [:]
        var latest: [String: Message] = [:]
        for message in messages {
            guard !message.id.isEmpty, records[message.id] == nil, message.conversationID == id,
                  message.revision > 0, message.revision < Int.max,
                  message.createdAt.timeIntervalSince1970.isFinite,
                  validConfidence(message.transcription?.confidence) else { throw ValidationError.invalidMessage }
            if message.purpose == .systemAssistance {
                guard message.modality == .written, message.senderRole != .aiPartner,
                      case .text = message.content, message.transcription == nil else { throw ValidationError.invalidMessage }
            } else if message.senderRole == .system { throw ValidationError.invalidMessage }
            if let attachment = message.audioAttachment {
                guard message.modality == .spoken,
                      attachment.storageKey == "fixture:turtle-partner" || Self.isRecordingKey(attachment.storageKey) else {
                    throw ValidationError.invalidMessage
                }
                if let duration = attachment.durationSeconds {
                    guard duration.isFinite, duration > 0, duration < Double(Int.max) / 2 else { throw ValidationError.invalidMessage }
                }
            }
            if let previousID = message.replacesMessageID {
                guard let previous = records[previousID], latest[message.logicalMessageID]?.id == previousID,
                      message.logicalMessageID == previous.logicalMessageID,
                      message.revision == previous.revision + 1,
                      message.senderRole == previous.senderRole, message.modality == previous.modality,
                      message.purpose == previous.purpose, message.replyToMessageID == previous.replyToMessageID else {
                    throw ValidationError.invalidEditChain
                }
            } else {
                guard message.id == message.logicalMessageID, message.revision == 1,
                      latest[message.logicalMessageID] == nil else { throw ValidationError.invalidEditChain }
            }
            if let replyID = message.replyToMessageID {
                guard records[replyID] != nil else { throw ValidationError.invalidMessage }
            }
            if let generation = message.generation {
                guard generation.requestID == message.id, UUID(uuidString: generation.requestID) != nil,
                      message.senderRole != .user, message.modality == .written,
                      message.status == .complete, message.origin == .interaction,
                      !generation.model.isEmpty, !generation.promptVersion.isEmpty,
                      case .text = message.content else { throw ValidationError.invalidMessage }
            }
            records[message.id] = message
            latest[message.logicalMessageID] = message
        }
        if let request = pendingReply?.request {
            guard UUID(uuidString: request.requestID) != nil, request.conversationID == id,
                  request.prompt == prompt, records[request.requestID] == nil else { throw ValidationError.invalidMessage }
            if let target = request.replyToMessageID {
                guard let message = records[target], message.senderRole == .user,
                      latest[message.logicalMessageID]?.id == target, request.messages.last?.id == target,
                      request.kind == (message.purpose == .systemAssistance ? .system : .partner) else {
                    throw ValidationError.invalidMessage
                }
            } else if !messages.isEmpty || !request.messages.isEmpty || request.kind != .partner {
                throw ValidationError.invalidMessage
            }
        }
        guard Set(grammarObservations.map(\.id)).count == grammarObservations.count,
              Set(grammarObservations.map { $0.metadata.messageID }).count == grammarObservations.count,
              Set(vocabularyObservations.map(\.id)).count == vocabularyObservations.count,
              Set(vocabularyObservations.map { $0.metadata.messageID }).count == vocabularyObservations.count,
              Set(textAnalyses.map(\.id)).count == textAnalyses.count,
              Set(textAnalyses.map { $0.metadata.messageID }).count == textAnalyses.count else {
            throw ValidationError.invalidObservation
        }
        for observation in grammarObservations {
            let text = try evaluatedText(observation.metadata, records: records)
            guard Set(observation.opportunities.map(\.id)).count == observation.opportunities.count else {
                throw ValidationError.invalidObservation
            }
            for opportunity in observation.opportunities {
                guard !opportunity.id.isEmpty, validCategory(opportunity.category),
                      validSpan(opportunity.textSpan, in: text), validConfidence(opportunity.confidence) else {
                    throw ValidationError.invalidObservation
                }
            }
        }
        for observation in vocabularyObservations {
            let text = try evaluatedText(observation.metadata, records: records)
            guard Set(observation.usages.map(\.id)).count == observation.usages.count else { throw ValidationError.invalidObservation }
            for usage in observation.usages {
                guard !usage.id.isEmpty, validSpan(usage.textSpan, in: text),
                      let range = Range(NSRange(location: usage.textSpan.startUTF16, length: usage.textSpan.lengthUTF16), in: text),
                      String(text[range]) == usage.surfaceText,
                      Set(usage.assessments.map(\.category)).count == usage.assessments.count else { throw ValidationError.invalidObservation }
                for assessment in usage.assessments {
                    guard validCategory(assessment.category), validConfidence(assessment.confidence) else {
                        throw ValidationError.invalidObservation
                    }
                }
            }
        }
        for analysis in textAnalyses {
            let text = try evaluatedText(analysis.metadata, records: records)
            try analysis.validate(text: text)
        }
    }

    static func isRecordingKey(_ key: String) -> Bool {
        key.hasSuffix(".caf") && UUID(uuidString: String(key.dropLast(4))) != nil
    }

    private func evaluatedText(_ metadata: ObservationMetadata, records: [String: Message]) throws -> String {
        guard !metadata.id.isEmpty, metadata.conversationID == id,
              let message = records[metadata.messageID], message.revision == metadata.messageRevision,
              message.senderRole == .user, message.purpose == .conversationPractice,
              metadata.evaluatedAt.timeIntervalSince1970.isFinite, validConfidence(metadata.confidence),
              !metadata.provenance.evaluatorID.isEmpty, !metadata.provenance.evaluatorVersion.isEmpty,
              !metadata.provenance.rubricVersion.isEmpty, !metadata.provenance.taxonomyVersion.isEmpty else {
            throw ValidationError.invalidObservation
        }
        switch metadata.textSource {
        case .messageText:
            guard case let .text(text) = message.content else { throw ValidationError.invalidObservation }
            return text
        case .speechTranscription:
            guard message.modality == .spoken, let transcript = message.transcription else { throw ValidationError.invalidObservation }
            return transcript.text
        }
    }

    private func validSpan(_ span: ObservationTextSpan, in text: String) -> Bool {
        span.range(in: text) != nil
    }

    private func validConfidence(_ value: Double?) -> Bool {
        value.map { $0.isFinite && (0...1).contains($0) } ?? true
    }

    private func validCategory(_ category: ObservationCategory) -> Bool {
        !category.categoryID.isEmpty && (category.subcategoryID.map { !$0.isEmpty } ?? true)
    }
}
