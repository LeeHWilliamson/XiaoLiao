struct ConversationSettings: Equatable {
    enum Tone: String, CaseIterable, Identifiable {
        case warm, casual, formal
        var id: String { rawValue }
        var title: String {
            switch self {
            case .warm: "温暖"
            case .casual: "随意"
            case .formal: "正式"
            }
        }
    }

    enum Vocabulary: String, CaseIterable, Identifiable {
        case simple, medium, complex
        var id: String { rawValue }
        var title: String {
            switch self {
            case .simple: "简单"
            case .medium: "中等"
            case .complex: "复杂"
            }
        }
    }

    enum ReplyLength: String, CaseIterable, Identifiable {
        case brief, medium, complex
        var id: String { rawValue }
        var title: String {
            switch self {
            case .brief: "简短"
            case .medium: "中等"
            // Retain Figma's label until the final product copy is supplied.
            case .complex: "复杂"
            }
        }
    }

    var tone: Tone = .casual
    var vocabulary: Vocabulary = .medium
    var replyLength: ReplyLength = .medium
}
