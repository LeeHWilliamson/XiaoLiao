import Foundation

/// Canonical conversation record, including immutable edit versions.
/// Each original/edit is an immutable record with its own ID and creation time.
/// Editing creates a new record instead of overwriting a version
/// that replies or observations may still reference.
nonisolated struct Message: Identifiable, Codable, Equatable, Sendable {
    enum SenderRole: String, Codable, Sendable {
        case user, aiPartner, system
    }

    /// App-level destination/purpose, not an AI provider's privileged system role.
    enum Purpose: String, Codable, Sendable {
        case conversationPractice, systemAssistance
    }

    /// Original communication method; showing a transcript does not change it.
    enum Modality: String, Codable, Sendable {
        case spoken, written
    }

    enum Status: String, Codable, Sendable {
        case pending, sending, streaming, complete, failed
    }

    enum Content: Codable, Equatable, Sendable {
        case text(String)
        case audio(AudioAttachment)
    }

    struct AudioAttachment: Codable, Equatable, Sendable {
        /// Storage-owned relative filename or opaque asset key, never raw audio
        /// bytes or an absolute installation-specific sandbox path.
        let storageKey: String
        let durationSeconds: TimeInterval?
    }

    struct Transcription: Codable, Equatable, Sendable {
        let text: String
        /// Recognizer-provided confidence in 0...1, or nil when unavailable.
        /// This is not a pronunciation assessment.
        let confidence: Double?
    }

    /// Unique ID of this exact version, not the whole edit chain.
    let id: String
    /// Stable across the edit chain; equals id on the original record.
    let logicalMessageID: String
    /// Previous version's id, or nil on the original. This is not a reply link.
    let replacesMessageID: String?
    let conversationID: String
    /// Creation time of this version; the original retains its own timestamp.
    let createdAt: Date
    let senderRole: SenderRole
    let purpose: Purpose
    let modality: Modality
    let content: Content
    /// Exact version being answered, rather than a logicalMessageID.
    let replyToMessageID: String?
    /// Starts at 1 for the original; each replacement advances it by one.
    let revision: Int
    let transcription: Transcription?
    let status: Status?

    init(id: String = UUID().uuidString, logicalMessageID: String? = nil,
         replacesMessageID: String? = nil, conversationID: String, createdAt: Date = Date(),
         senderRole: SenderRole, purpose: Purpose = .conversationPractice,
         modality: Modality, content: Content, replyToMessageID: String? = nil,
         revision: Int = 1, transcription: Transcription? = nil, status: Status? = .complete) {
        self.id = id
        self.logicalMessageID = logicalMessageID ?? id
        self.replacesMessageID = replacesMessageID
        self.conversationID = conversationID
        self.createdAt = createdAt
        self.senderRole = senderRole
        self.purpose = purpose
        self.modality = modality
        self.content = content
        self.replyToMessageID = replyToMessageID
        self.revision = revision
        self.transcription = transcription
        self.status = status
    }

    /// Derived from the chain link so a separate stored flag cannot disagree.
    var isEdit: Bool { replacesMessageID != nil }

    var audioAttachment: AudioAttachment? {
        guard case let .audio(attachment) = content else { return nil }
        return attachment
    }

    /// Storage relocation changes the attachment reference, not the message version.
    func relocatingAudio(to storageKey: String) -> Message {
        guard let attachment = audioAttachment else { return self }
        return Message(id: id, logicalMessageID: logicalMessageID, replacesMessageID: replacesMessageID,
                       conversationID: conversationID, createdAt: createdAt, senderRole: senderRole,
                       purpose: purpose, modality: modality,
                       content: .audio(AudioAttachment(storageKey: storageKey, durationSeconds: attachment.durationSeconds)),
                       replyToMessageID: replyToMessageID, revision: revision, transcription: transcription, status: status)
    }

    func edited(content: Content, transcription: Transcription? = nil) -> Message {
        Message(logicalMessageID: logicalMessageID, replacesMessageID: id,
                conversationID: conversationID, senderRole: senderRole, purpose: purpose,
                modality: modality, content: content, replyToMessageID: replyToMessageID,
                revision: revision + 1, transcription: transcription, status: .complete)
    }
}
