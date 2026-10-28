import Foundation

struct ConversationMessage: Identifiable, Equatable {
    enum Sender: Equatable {
        case partner, learner
    }

    enum CommunicationMethod: Equatable {
        case voice, text
    }

    enum Content: Equatable {
        case audio(duration: Int, transcript: String)
        case text(String)
    }

    let id: String
    let sender: Sender
    // Keep the original send method even when the composer changes or text is edited.
    let communicationMethod: CommunicationMethod
    var content: Content
    // This is fixture copy, not the result of a translation service.
    var mockTranslation: String?
    // Real local audio has no invented transcript or translation.
    var localAudio: LocalAudioClip? = nil

    var actions: [MessageAction] {
        switch content {
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
