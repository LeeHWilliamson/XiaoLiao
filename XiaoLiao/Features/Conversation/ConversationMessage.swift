import Foundation

nonisolated struct ConversationMessage: Identifiable, Equatable, Codable {
    enum Sender: String, Equatable, Codable {
        case partner, learner, system
    }

    enum Purpose: String, Equatable, Codable {
        case conversation, system
    }

    enum CommunicationMethod: String, Equatable, Codable {
        case voice, text
    }

    enum Content: Equatable, Codable {
        case audio(duration: Int, transcript: String)
        case text(String)
    }

    let id: String
    let sender: Sender
    // Keep the original send method even when the composer changes or text is edited.
    let communicationMethod: CommunicationMethod
    let purpose: Purpose
    var content: Content
    // This is fixture copy, not the result of a translation service.
    var mockTranslation: String?
    // Real local audio has no invented transcript or translation.
    var localAudio: LocalAudioClip? = nil

    init(id: String, sender: Sender, communicationMethod: CommunicationMethod, content: Content,
         mockTranslation: String? = nil, localAudio: LocalAudioClip? = nil, purpose: Purpose = .conversation) {
        self.id = id
        self.sender = sender
        self.communicationMethod = communicationMethod
        self.content = content
        self.mockTranslation = mockTranslation
        self.localAudio = localAudio
        self.purpose = purpose
    }

    private enum CodingKeys: String, CodingKey {
        case id, sender, communicationMethod, purpose, content, mockTranslation, localAudio
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        sender = try values.decode(Sender.self, forKey: .sender)
        communicationMethod = try values.decode(CommunicationMethod.self, forKey: .communicationMethod)
        purpose = try values.decodeIfPresent(Purpose.self, forKey: .purpose) ?? .conversation
        content = try values.decode(Content.self, forKey: .content)
        mockTranslation = try values.decodeIfPresent(String.self, forKey: .mockTranslation)
        localAudio = try values.decodeIfPresent(LocalAudioClip.self, forKey: .localAudio)
    }

    var actions: [MessageAction] {
        // The blue-message designs have no action rails or spoken responses.
        guard purpose == .conversation, sender != .system else { return [] }
        return switch content {
        case .audio: [.transcribe, .translate, .repeatAudio]
        case .text: sender == .learner ? [.translate, .play, .edit] : [.translate, .play]
        }
    }
}

enum MessageAction: String, Identifiable {
    case transcribe, translate, repeatAudio, play, edit

    var id: String { rawValue }

    var label: String {
        switch self {
        case .transcribe: "转写"
        case .translate: "翻译"
        case .repeatAudio: "重新生成"
        case .play: "播放"
        case .edit: "编辑"
        }
    }
}
