import Foundation

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

@MainActor
extension Message {
    var actions: [MessageAction] {
        guard purpose == .conversationPractice, senderRole != .system else { return [] }
        if senderRole == .aiPartner, case .audio = content { return [.transcribe, .translate, .repeatAudio] }
        return senderRole == .user ? [.translate, .play, .edit] : [.translate, .play]
    }
}
