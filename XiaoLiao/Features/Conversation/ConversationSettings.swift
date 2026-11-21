import Foundation
import Observation

nonisolated struct ConversationSettings: Equatable, Codable, Sendable {
    enum Tone: String, CaseIterable, Identifiable, Codable, Sendable {
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

    enum Vocabulary: String, CaseIterable, Identifiable, Codable, Sendable {
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

    enum ReplyLength: String, CaseIterable, Identifiable, Codable, Sendable {
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

    enum Key: String, Codable, CaseIterable, Hashable, Sendable { case tone, vocabulary, replyLength }

    func changedKeys(comparedTo other: Self) -> [Key] {
        Key.allCases.filter { key in
            switch key {
            case .tone: tone != other.tone
            case .vocabulary: vocabulary != other.vocabulary
            case .replyLength: replyLength != other.replyLength
            }
        }
    }

    var tone: Tone = .casual
    var vocabulary: Vocabulary = .medium
    var replyLength: ReplyLength = .medium
}

/// Explicit app-wide guidance only. No inference, telemetry or backend profile store.
@MainActor
@Observable
final class LearningPreferencesStore {
    static let maximumLength = 2000
    private(set) var text: String
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let key: String

    init(defaults: UserDefaults? = nil, key: String = "XiaoLiao.LearningPreferences") {
        self.defaults = defaults
        self.key = key
        text = defaults?.string(forKey: key) ?? ""
    }

    static func configured() -> LearningPreferencesStore {
        var key = "XiaoLiao.LearningPreferences"
        #if DEBUG
        if let id = ProcessInfo.processInfo.environment["XIAOLIAO_UI_TEST_STORE"], UUID(uuidString: id) != nil {
            key += ".ui-test.\(id)"
        }
        #endif
        return LearningPreferencesStore(defaults: .standard, key: key)
    }

    func save(_ draft: String) throws {
        guard draft.utf16.count <= Self.maximumLength else { throw PreferenceError.tooLong }
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults?.set(value, forKey: key)
        text = value
    }

    nonisolated enum PreferenceError: Error, LocalizedError {
        case tooLong
        var errorDescription: String? { "Learning preferences must be 2,000 characters or fewer." }
    }
}
