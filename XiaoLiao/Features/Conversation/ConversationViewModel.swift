import Foundation
import Observation

@MainActor
@Observable
final class ConversationViewModel {
    enum InputMode: Equatable { case voice, text }
    enum Detail: Equatable { case transcript, translation }

    var prompt = ""
    var draft = ""
    var inputMode: InputMode = .voice
    private(set) var messages: [ConversationMessage] = []
    private(set) var selectedMessageID: String?
    private(set) var editingMessageID: String?
    private(set) var details: [String: Detail] = [:]

    var canStart: Bool { !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func suggestPrompt() {
        prompt = MockConversation.prompt
    }

    @discardableResult
    func startConversation() -> Bool {
        guard canStart else { return false }
        messages = MockConversation.messages
        selectedMessageID = nil
        details = [:]
        draft = ""
        editingMessageID = nil
        inputMode = .voice
        return true
    }

    func selectMessage(_ id: String) {
        guard messages.contains(where: { $0.id == id }) else { return }
        selectedMessageID = selectedMessageID == id ? nil : id
    }

    func deselectMessage() {
        selectedMessageID = nil
    }

    func isAvailable(_ action: MessageAction, for message: ConversationMessage) -> Bool {
        guard message.actions.contains(action) else { return false }
        switch action {
        case .transcribe, .edit: return true
        case .translate: return message.mockTranslation != nil
        case .play, .repeatAudio: return false // No audio files or service in milestone one.
        }
    }

    func perform(_ action: MessageAction, on id: String) {
        guard selectedMessageID == id,
              let message = messages.first(where: { $0.id == id }),
              isAvailable(action, for: message) else { return }
        switch action {
        case .transcribe:
            toggleDetail(.transcript, for: id)
        case .translate:
            toggleDetail(.translation, for: id)
        case .edit:
            guard case let .text(text) = message.content else { return }
            editingMessageID = id
            draft = text
            inputMode = .text
        case .play, .repeatAudio:
            break
        }
    }

    func detailText(for message: ConversationMessage) -> String? {
        switch details[message.id] {
        case .transcript:
            guard case let .audio(_, transcript) = message.content else { return nil }
            return transcript
        case .translation:
            return message.mockTranslation
        case nil:
            return nil
        }
    }

    @discardableResult
    func submitDraft() -> Bool {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        if let id = editingMessageID {
            guard let index = messages.firstIndex(where: { $0.id == id }),
                  case .text = messages[index].content else { return false }
            messages[index].content = .text(text)
            // An edited sentence no longer has a valid canned translation.
            messages[index].mockTranslation = nil
            details[id] = nil
        } else {
            messages.append(ConversationMessage(id: UUID().uuidString, content: .text(text)))
        }
        draft = ""
        editingMessageID = nil
        selectedMessageID = nil
        return true
    }

    func showVoiceInput() {
        inputMode = .voice
        draft = ""
        editingMessageID = nil
    }

    private func toggleDetail(_ detail: Detail, for id: String) {
        details[id] = details[id] == detail ? nil : detail
    }
}
