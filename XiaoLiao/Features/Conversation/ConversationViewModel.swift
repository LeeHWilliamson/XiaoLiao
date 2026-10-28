import Foundation
import Observation

@MainActor
@Observable
final class ConversationViewModel {
    enum InputMode: Equatable { case voice, text }
    enum Detail: Equatable { case transcript, translation, playback }

    let audio: ConversationAudioController

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

    init(history: [ConversationSession]? = nil, audio: ConversationAudioController? = nil) {
        self.history = history ?? MockConversation.history
        self.audio = audio ?? ConversationAudioController()
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
        if selectedMessageID != id { audio.stopPlayback() }
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
        guard !audio.hasDraft else { return false }
        switch action {
        case .transcribe: return true
        case .edit: return canEditMessage(message.id)
        case .translate: return message.mockTranslation != nil
        case .play:
            return message.localAudio.map { FileManager.default.fileExists(atPath: $0.url.path) } ?? false
        case .repeatAudio: return false // Regeneration requires future service integration.
        }
    }

    func perform(_ action: MessageAction, on id: String) {
        guard selectedMessageID == id,
              let message = messages.first(where: { $0.id == id }),
              isAvailable(action, for: message) else { return }
        switch action {
        case .transcribe:
            audio.stopPlayback()
            toggleDetail(.transcript, for: id)
        case .translate:
            audio.stopPlayback()
            toggleDetail(.translation, for: id)
        case .edit:
            guard case let .text(text) = message.content else { return }
            audio.stopPlayback()
            details[id] = nil
            editingMessageID = id
            if message.localAudio != nil {
                draft = ""
                inputMode = .voice
                audio.startRecording()
            } else {
                draft = text
                inputMode = .text
            }
        case .play:
            guard let clip = message.localAudio else { return }
            details[id] = .playback
            audio.togglePlayback(clip, id: id)
        case .repeatAudio:
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
        case .playback, nil:
            return nil
        }
    }

    @discardableResult
    func submitDraft() -> Bool {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !audio.hasDraft else { return false }
        if let id = editingMessageID {
            guard canEditMessage(id),
                  let index = messages.firstIndex(where: { $0.id == id }),
                  messages[index].localAudio == nil,
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
        audio.stopPlayback()
        draft = ""
        editingMessageID = nil
        selectedMessageID = nil
        saveActiveConversation()
        return true
    }

    func showVoiceInput() {
        cancelAudioDraft()
        inputMode = .voice
        draft = ""
        editingMessageID = nil
    }

    func showTextInput() {
        cancelAudioDraft()
        inputMode = .text
    }

    func beginRecording() {
        guard activeSessionID != nil, !audio.hasDraft else { return }
        draft = ""
        editingMessageID = nil
        selectedMessageID = nil
        audio.startRecording()
    }

    @discardableResult
    func sendRecording() async -> Bool {
        guard let sessionID = activeSessionID, audio.canSend else { return false }
        let replacementID = editingMessageID
        guard let clip = await audio.finishDraft() else { return false }
        guard commitRecording(clip, in: sessionID, replacing: replacementID) else {
            audio.discard(clip)
            return false
        }
        return true
    }

    /// Commit only after real audio has finalized. Recheck session and edit policy
    /// after asynchronous work so navigation or a later message cannot replace the wrong reply.
    @discardableResult
    func commitRecording(_ clip: LocalAudioClip, in sessionID: String, replacing id: String? = nil) -> Bool {
        guard activeSessionID == sessionID, clip.duration.isFinite, clip.duration > 0,
              FileManager.default.fileExists(atPath: clip.url.path) else { return false }
        let label = "语音消息 · \(clip.durationLabel)"
        if let id {
            guard editingMessageID == id, canEditMessage(id),
                  let index = messages.firstIndex(where: { $0.id == id }),
                  let previous = messages[index].localAudio else { return false }
            messages[index].content = .text(label)
            messages[index].localAudio = clip
            messages[index].mockTranslation = nil
            details[id] = nil
            if previous.url != clip.url { audio.discard(previous) }
        } else {
            guard editingMessageID == nil else { return false }
            messages.append(ConversationMessage(
                id: UUID().uuidString,
                sender: .learner,
                communicationMethod: .voice,
                content: .text(label),
                localAudio: clip
            ))
        }
        draft = ""
        editingMessageID = nil
        selectedMessageID = nil
        saveActiveConversation()
        return true
    }

    func cancelAudioDraft() {
        audio.cancelDraft()
        audio.issue = nil
        if inputMode == .voice { editingMessageID = nil }
    }

    func leaveFeed() {
        cancelAudioDraft()
        audio.stopPlayback()
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
        leaveFeed()
        selectedMessageID = nil
        details = [:]
        draft = ""
        editingMessageID = nil
        inputMode = .voice
    }
}
