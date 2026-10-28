import Foundation

struct ConversationMessage: Identifiable, Equatable {
    enum Content: Equatable {
        case audio(duration: Int, transcript: String)
        case text(String)
    }

    let id: String
    var content: Content
    // This is fixture copy, not the result of a translation service.
    var mockTranslation: String?

    var actions: [MessageAction] {
        switch content {
        case .audio: [.transcribe, .translate, .repeatAudio]
        case .text: [.translate, .play, .edit]
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
