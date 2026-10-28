import Foundation
import Observation

@MainActor
@Observable
final class ConversationViewModel {
    enum InputMode: Equatable { case voice, text }
    enum Detail: Equatable { case transcript, translation, playback }

    let audio: ConversationAudioController

    struct StorageIssue: Equatable {
        let message: String
        var canRetryLoading = false
    }
    var storageIssue: StorageIssue?
    @ObservationIgnored private var historyStore: ConversationHistoryStore?
    @ObservationIgnored private var storageDirectory: URL?
    @ObservationIgnored private var isStorageReady = false
    @ObservationIgnored private var isRestoringSettings = false

    var prompt = ""
    var draft = ""
    var inputMode: InputMode = .voice
    private(set) var isSystemMessageMode = false
    @ObservationIgnored private var inputModeBeforeSystem: InputMode = .voice
    var settings = ConversationSettings() {
        didSet {
            guard !isRestoringSettings else { return }
            if !saveActiveConversation() {
                isRestoringSettings = true
                settings = oldValue
                isRestoringSettings = false
            }
        }
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

    /// The app opts into disk storage explicitly; tests and previews stay isolated.
    static func persistent(directory: URL? = nil) -> ConversationViewModel {
        let model = ConversationViewModel(history: [])
        model.storageDirectory = directory ?? ConversationHistoryStore.defaultDirectory
        model.retryLoadingHistory()
        return model
    }

    static func persistent(store: ConversationHistoryStore) -> ConversationViewModel {
        let model = ConversationViewModel(history: [])
        model.storageDirectory = store.directory
        model.historyStore = store
        model.retryLoadingHistory()
        return model
    }

    func retryLoadingHistory() {
        guard let storageDirectory else { return }
        do {
            let store = try historyStore ?? ConversationHistoryStore(directory: storageDirectory)
            let sessions = try store.load()
            historyStore = store
            isStorageReady = true
            history = sessions
            storageIssue = sessions.flatMap(\.messages).contains(where: {
                $0.localAudio.map { !FileManager.default.fileExists(atPath: $0.url.path) } ?? false
            }) ? StorageIssue(message: "部分录音文件暂不可用。对话文字和设置仍已保留。") : nil
        } catch {
            isStorageReady = false
            storageIssue = StorageIssue(message: "无法读取本地历史。已有数据未被清除。请稍后重试。", canRetryLoading: true)
        }
    }

    var canStart: Bool { !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func suggestPrompt() {
        prompt = MockConversation.prompt
    }

    @discardableResult
    func startConversation() -> Bool {
        guard canStart else { return false }
        let session = ConversationSession(
            id: UUID().uuidString,
            title: prompt == MockConversation.prompt ? "乌龟" : String(prompt.trimmingCharacters(in: .whitespacesAndNewlines).prefix(12)),
            prompt: prompt,
            messages: MockConversation.messages,
            settings: settings
        )
        guard let saved = persist(session) else { return false }
        activeSessionID = nil
        messages = saved.messages
        resetPresentation()
        history.insert(saved, at: 0)
        activeSessionID = saved.id
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
        case .edit: return !isSystemMessageMode && canEditMessage(message.id)
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
        if isSystemMessageMode { return submitSystemMessage(text) }
        var updated = messages
        if let id = editingMessageID {
            guard canEditMessage(id),
                  let index = messages.firstIndex(where: { $0.id == id }),
                  messages[index].localAudio == nil,
                  case .text = messages[index].content else { return false }
            updated[index].content = .text(text)
            // An edited sentence no longer has a valid canned translation.
            updated[index].mockTranslation = nil
        } else {
            updated.append(ConversationMessage(
                id: UUID().uuidString,
                sender: .learner,
                communicationMethod: .text,
                content: .text(text)
            ))
        }
        guard commitMessages(updated) else { return false }
        if let id = editingMessageID { details[id] = nil }
        audio.stopPlayback()
        draft = ""
        editingMessageID = nil
        selectedMessageID = nil
        return true
    }

    func showVoiceInput() {
        guard !isSystemMessageMode else { return }
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
        guard activeSessionID != nil, !audio.hasDraft, !isSystemMessageMode else { return }
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
            // A storage failure keeps the review row/clip available for retry.
            // Navigation cancellation already invalidates and deletes its own draft.
            return false
        }
        audio.completeSend()
        return true
    }

    /// Commit only after real audio has finalized. Recheck session and edit policy
    /// after asynchronous work so navigation or a later message cannot replace the wrong reply.
    @discardableResult
    func commitRecording(_ clip: LocalAudioClip, in sessionID: String, replacing id: String? = nil) -> Bool {
        guard !isSystemMessageMode, activeSessionID == sessionID, clip.duration.isFinite, clip.duration > 0, clip.duration < Double(Int.max) / 2,
              FileManager.default.fileExists(atPath: clip.url.path) else { return false }
        let label = "语音消息 · \(clip.durationLabel)"
        var updated = messages
        var previousClip: LocalAudioClip?
        if let id {
            guard editingMessageID == id, canEditMessage(id),
                  let index = messages.firstIndex(where: { $0.id == id }),
                  let previous = messages[index].localAudio else { return false }
            updated[index].content = .text(label)
            updated[index].localAudio = clip
            updated[index].mockTranslation = nil
            previousClip = previous
        } else {
            guard editingMessageID == nil else { return false }
            updated.append(ConversationMessage(
                id: UUID().uuidString,
                sender: .learner,
                communicationMethod: .voice,
                content: .text(label),
                localAudio: clip
            ))
        }
        guard commitMessages(updated) else { return false }
        if let id { details[id] = nil }
        if let previousClip, previousClip.url != clip.url, historyStore?.owns(previousClip) != true {
            audio.discard(previousClip)
        }
        if let historyStore, !historyStore.owns(clip) {
            audio.discard(clip)
        }
        draft = ""
        editingMessageID = nil
        selectedMessageID = nil
        return true
    }

    func cancelAudioDraft() {
        audio.cancelDraft()
        audio.issue = nil
        if inputMode == .voice { editingMessageID = nil }
    }

    func leaveFeed() {
        if isSystemMessageMode {
            draft = ""
            endSystemMessageMode()
        }
        cancelAudioDraft()
        audio.stopPlayback()
    }

    func toggleSystemMessageMode() {
        guard activeSessionID != nil, !audio.hasDraft else { return }
        audio.stopPlayback()
        selectedMessageID = nil
        if isSystemMessageMode {
            endSystemMessageMode()
        } else {
            // Switching destinations cancels an edit rather than resending its old text.
            if editingMessageID != nil { draft = "" }
            editingMessageID = nil
            inputModeBeforeSystem = inputMode
            inputMode = .text
            isSystemMessageMode = true
        }
    }

    private func endSystemMessageMode() {
        isSystemMessageMode = false
        inputMode = inputModeBeforeSystem
    }

    private func submitSystemMessage(_ text: String) -> Bool {
        let response = MockConversation.systemResponse(for: text, settings: settings)
        var updatedSettings = settings
        if let vocabulary = response.vocabulary { updatedSettings.vocabulary = vocabulary }
        let exchange = [
            ConversationMessage(id: UUID().uuidString, sender: .learner, communicationMethod: .text,
                                content: .text(text), purpose: .system),
            ConversationMessage(id: UUID().uuidString, sender: .system, communicationMethod: .text,
                                content: .text(response.text), purpose: .system)
        ]
        // Request, mock reply, and any local setting change form one saved snapshot.
        guard commitMessages(messages + exchange, settings: updatedSettings) else { return false }
        draft = ""
        selectedMessageID = nil
        editingMessageID = nil
        endSystemMessageMode()
        return true
    }

    private func toggleDetail(_ detail: Detail, for id: String) {
        details[id] = details[id] == detail ? nil : detail
    }

    @discardableResult
    private func saveActiveConversation() -> Bool {
        guard let id = activeSessionID,
              history.contains(where: { $0.id == id }) else { return true }
        return commitMessages(messages)
    }

    private func commitMessages(_ updated: [ConversationMessage], settings updatedSettings: ConversationSettings? = nil) -> Bool {
        guard let id = activeSessionID,
              let index = history.firstIndex(where: { $0.id == id }) else { return false }
        var session = history[index]
        session.messages = updated
        session.settings = updatedSettings ?? settings
        guard let saved = persist(session) else { return false }
        history[index] = saved
        messages = saved.messages
        if settings != saved.settings {
            isRestoringSettings = true
            settings = saved.settings
            isRestoringSettings = false
        }
        return true
    }

    private func persist(_ session: ConversationSession) -> ConversationSession? {
        guard storageDirectory != nil else { return session }
        guard isStorageReady, let historyStore else {
            storageIssue = StorageIssue(message: "本地历史尚未打开，操作未保存。请重试读取历史。", canRetryLoading: true)
            return nil
        }
        do {
            let saved = try historyStore.save(session)
            storageIssue = nil
            return saved
        } catch {
            storageIssue = StorageIssue(message: "无法保存本地历史，操作尚未完成。请检查可用储存空间后重试；原有对话仍已保留。")
            return nil
        }
    }

    private func canEditMessage(_ id: String) -> Bool {
        guard let latest = messages.last(where: { $0.sender == .learner }),
              latest.id == id,
              latest.purpose == .conversation,
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
