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
    var settings = ConversationSettings() {
        didSet { saveActiveConversation() }
    }
    private(set) var history: [ConversationSession]
    private(set) var activeSessionID: String?
    private(set) var messages: [ConversationMessage] = []
    private(set) var selectedMessageID: String?
    private(set) var editingMessageID: String?
    private(set) var details: [String: Detail] = [:]

    init(history: [ConversationSession]? = nil) {
        self.history = history ?? MockConversation.history
    }

    var canStart: Bool { !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func suggestPrompt() {
        prompt = MockConversation.prompt
    }

    @discardableResult
    func startConversation() -> Bool {
        guard canStart else { return false }
        activeSessionID = nil
        messages = MockConversation.messages
        resetPresentation()
        let session = ConversationSession(
            id: UUID().uuidString,
            title: prompt == MockConversation.prompt ? "乌龟" : String(prompt.trimmingCharacters(in: .whitespacesAndNewlines).prefix(12)),
            prompt: prompt,
            messages: messages,
            settings: settings
        )
        history.insert(session, at: 0)
        activeSessionID = session.id
        return true
    }

    @discardableResult
    func openConversation(_ id: String) -> Bool {
        guard let session = history.first(where: { $0.id == id }) else { return false }
        // Disable snapshot writes until all the selected session's state is restored.
        activeSessionID = nil
        prompt = session.prompt
        messages = session.messages
        settings = session.settings
        resetPresentation()
        activeSessionID = session.id
        return true
    }

    func prepareNewConversation() {
        activeSessionID = nil
        prompt = ""
        messages = []
        settings = ConversationSettings()
        resetPresentation()
    }

    func selectMessage(_ id: String) {
        guard messages.contains(where: { $0.id == id }) else { return }
        selectedMessageID = selectedMessageID == id ? nil : id
    }

    func deselectMessage() {
        selectedMessageID = nil
    }

    func actions(for message: ConversationMessage) -> [MessageAction] {
        message.actions.filter { $0 != .edit || canEditMessage(message.id) }
    }

    func isAvailable(_ action: MessageAction, for message: ConversationMessage) -> Bool {
        guard message.actions.contains(action) else { return false }
        switch action {
        case .transcribe: return true
        case .edit: return canEditMessage(message.id)
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
            guard canEditMessage(id),
                  let index = messages.firstIndex(where: { $0.id == id }),
                  case .text = messages[index].content else { return false }
            messages[index].content = .text(text)
            // An edited sentence no longer has a valid canned translation.
            messages[index].mockTranslation = nil
            details[id] = nil
        } else {
            messages.append(ConversationMessage(
                id: UUID().uuidString,
                sender: .learner,
                communicationMethod: .text,
                content: .text(text)
            ))
        }
        draft = ""
        editingMessageID = nil
        selectedMessageID = nil
        saveActiveConversation()
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

    private func saveActiveConversation() {
        guard let id = activeSessionID,
              let index = history.firstIndex(where: { $0.id == id }) else { return }
        history[index].messages = messages
        history[index].settings = settings
    }

    private func canEditMessage(_ id: String) -> Bool {
        guard let latest = messages.last(where: { $0.sender == .learner }),
              latest.id == id,
              case .text = latest.content else { return false }
        return true
    }

    private func resetPresentation() {
        selectedMessageID = nil
        details = [:]
        draft = ""
        editingMessageID = nil
        inputMode = .voice
    }
}
