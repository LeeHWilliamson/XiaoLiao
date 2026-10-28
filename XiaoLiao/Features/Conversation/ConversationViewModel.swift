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
    private(set) var messageVersions: [Message] = []
    var messages: [Message] { ConversationSession.latestVersions(in: messageVersions) }
    private(set) var grammarObservations: [GrammarObservation] = []
    private(set) var vocabularyObservations: [VocabularyObservation] = []
    @ObservationIgnored private var temporaryRecordings: [String: LocalAudioClip] = [:]
    private(set) var selectedMessageID: String?
    private(set) var editingMessageID: String?
    private(set) var details: [String: Detail] = [:]

    init(history: [ConversationSession]? = nil, audio: ConversationAudioController? = nil) {
        self.history = history ?? MockConversation.history
        self.audio = audio ?? ConversationAudioController()
    }

    /// The app opts into disk storage explicitly; tests and previews stay isolated.
    static func persistent(directory: URL? = nil, audio: ConversationAudioController? = nil) -> ConversationViewModel {
        let model = ConversationViewModel(history: [], audio: audio)
        model.storageDirectory = directory ?? ConversationHistoryStore.defaultDirectory
        model.retryLoadingHistory()
        return model
    }

    static func persistent(store: ConversationHistoryStore, audio: ConversationAudioController? = nil) -> ConversationViewModel {
        let model = ConversationViewModel(history: [], audio: audio)
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
                guard let attachment = $0.audioAttachment, let url = store.recordingURL(for: attachment.storageKey) else { return false }
                return !FileManager.default.fileExists(atPath: url.path)
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
        let sessionID = UUID().uuidString
        let session = ConversationSession(
            id: sessionID,
            title: prompt == MockConversation.prompt ? "乌龟" : String(prompt.trimmingCharacters(in: .whitespacesAndNewlines).prefix(12)),
            prompt: prompt,
            messages: MockConversation.messages(conversationID: sessionID, createdAt: Date()),
            settings: settings
        )
        guard let saved = persist(session) else { return false }
        activeSessionID = nil
        messageVersions = saved.messages
        grammarObservations = saved.grammarObservations
        vocabularyObservations = saved.vocabularyObservations
        resetPresentation()
        history.insert(saved, at: 0)
        activeSessionID = saved.id
        return true
    }

    @discardableResult
    func openConversation(_ id: String) -> Bool {
        guard let session = history.first(where: { $0.id == id }) else { return false }
        guard (try? session.validate()) != nil else { return false }
        // Disable snapshot writes until all the selected session's state is restored.
        activeSessionID = nil
        prompt = session.prompt
        messageVersions = session.messages
        grammarObservations = session.grammarObservations
        vocabularyObservations = session.vocabularyObservations
        settings = session.settings
        resetPresentation()
        activeSessionID = session.id
        return true
    }

    func prepareNewConversation() {
        activeSessionID = nil
        prompt = ""
        messageVersions = []
        grammarObservations = []
        vocabularyObservations = []
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

    func actions(for message: Message) -> [MessageAction] {
        message.actions.filter { $0 != .edit || canEditMessage(message.id) }
    }

    func isAvailable(_ action: MessageAction, for message: Message) -> Bool {
        guard messages.contains(where: { $0.id == message.id }), message.actions.contains(action) else { return false }
        guard !audio.hasDraft else { return false }
        switch action {
        case .transcribe: return message.transcription != nil
        case .edit: return !isSystemMessageMode && canEditMessage(message.id)
        case .translate: return translation(for: message) != nil
        case .play:
            return audioClip(for: message) != nil
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
            audio.stopPlayback()
            details[id] = nil
            editingMessageID = id
            if message.audioAttachment != nil {
                draft = ""
                inputMode = .voice
                audio.startRecording()
            } else if case let .text(text) = message.content {
                draft = text
                inputMode = .text
            }
        case .play:
            guard let clip = audioClip(for: message) else { return }
            details[id] = .playback
            audio.togglePlayback(clip, id: id)
        case .repeatAudio:
            break
        }
    }

    func detailText(for message: Message) -> String? {
        switch details[message.id] {
        case .transcript:
            return message.transcription?.text
        case .translation:
            return translation(for: message)
        case .playback, nil:
            return nil
        }
    }

    @discardableResult
    func submitDraft() -> Bool {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !audio.hasDraft else { return false }
        if isSystemMessageMode { return submitSystemMessage(text) }
        guard let sessionID = activeSessionID else { return false }
        var updated = messageVersions
        if let id = editingMessageID {
            guard canEditMessage(id), let original = messages.first(where: { $0.id == id }),
                  original.audioAttachment == nil, case .text = original.content else { return false }
            let transcript: Message.Transcription? = original.modality == .spoken ? .init(text: text, confidence: nil) : nil
            updated.append(original.edited(content: .text(text), transcription: transcript))
        } else {
            updated.append(Message(conversationID: sessionID, senderRole: .user, modality: .written,
                                   content: .text(text), replyToMessageID: lastPartnerMessageID))
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
        var updated = messageVersions
        let key = clip.url.lastPathComponent
        guard ConversationSession.isRecordingKey(key) else { return false }
        let attachment = Message.AudioAttachment(storageKey: key, durationSeconds: clip.duration)
        if let id {
            guard editingMessageID == id, canEditMessage(id),
                  let original = messages.first(where: { $0.id == id }), original.audioAttachment != nil else { return false }
            updated.append(original.edited(content: .audio(attachment)))
        } else {
            guard editingMessageID == nil else { return false }
            updated.append(Message(conversationID: sessionID, senderRole: .user, modality: .spoken,
                                   content: .audio(attachment), replyToMessageID: lastPartnerMessageID))
        }
        temporaryRecordings[key] = clip
        guard commitMessages(updated) else { return false }
        if let id { details[id] = nil }
        // Old recordings remain referenced by their immutable message versions.
        if historyStore != nil {
            temporaryRecordings[key] = nil
            audio.discard(clip)
        }
        draft = ""
        editingMessageID = nil
        selectedMessageID = nil
        return true
    }

    func cancelAudioDraft() {
        if let clip = audio.reviewClip { temporaryRecordings[clip.url.lastPathComponent] = nil }
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
        guard let sessionID = activeSessionID else { return false }
        let request = Message(conversationID: sessionID, senderRole: .user, purpose: .systemAssistance,
                              modality: .written, content: .text(text))
        let reply = Message(conversationID: sessionID, senderRole: .system, purpose: .systemAssistance,
                            modality: .written, content: .text(response.text), replyToMessageID: request.id)
        guard commitMessages(messageVersions + [request, reply], settings: updatedSettings) else { return false }
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
        return commitMessages(messageVersions)
    }

    private func commitMessages(_ updated: [Message], settings updatedSettings: ConversationSettings? = nil) -> Bool {
        guard let id = activeSessionID,
              let index = history.firstIndex(where: { $0.id == id }) else { return false }
        var session = history[index]
        session.messages = updated
        session.settings = updatedSettings ?? settings
        return commitSession(session)
    }

    private func commitSession(_ session: ConversationSession) -> Bool {
        guard let index = history.firstIndex(where: { $0.id == session.id }),
              let saved = persist(session) else { return false }
        history[index] = saved
        messageVersions = saved.messages
        grammarObservations = saved.grammarObservations
        vocabularyObservations = saved.vocabularyObservations
        if settings != saved.settings {
            isRestoringSettings = true
            settings = saved.settings
            isRestoringSettings = false
        }
        return true
    }

    @discardableResult
    func recordGrammarObservation(_ observation: GrammarObservation) -> Bool {
        guard let index = history.firstIndex(where: { $0.id == activeSessionID }) else { return false }
        var session = history[index]
        session.grammarObservations.removeAll { $0.metadata.messageID == observation.metadata.messageID }
        session.grammarObservations.append(observation)
        return commitSession(session)
    }

    @discardableResult
    func recordVocabularyObservation(_ observation: VocabularyObservation) -> Bool {
        guard let index = history.firstIndex(where: { $0.id == activeSessionID }) else { return false }
        var session = history[index]
        session.vocabularyObservations.removeAll { $0.metadata.messageID == observation.metadata.messageID }
        session.vocabularyObservations.append(observation)
        return commitSession(session)
    }

    func translation(for message: Message) -> String? { MockConversation.translation(for: message) }

    func audioClip(for message: Message) -> LocalAudioClip? {
        guard let attachment = message.audioAttachment,
              let duration = attachment.durationSeconds,
              ConversationSession.isRecordingKey(attachment.storageKey) else { return nil }
        if let temporary = temporaryRecordings[attachment.storageKey], FileManager.default.fileExists(atPath: temporary.url.path) {
            return temporary
        }
        guard let url = historyStore?.recordingURL(for: attachment.storageKey),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return LocalAudioClip(url: url, duration: duration)
    }

    private var lastPartnerMessageID: String? {
        messages.last(where: { $0.senderRole == .aiPartner && $0.purpose == .conversationPractice })?.id
    }

    private func persist(_ session: ConversationSession) -> ConversationSession? {
        do { try session.validate() } catch {
            storageIssue = StorageIssue(message: "对话数据无效，操作未保存。")
            return nil
        }
        guard storageDirectory != nil else { return session }
        guard isStorageReady, let historyStore else {
            storageIssue = StorageIssue(message: "本地历史尚未打开，操作未保存。请重试读取历史。", canRetryLoading: true)
            return nil
        }
        do {
            let saved = try historyStore.save(session, recordingSources: temporaryRecordings.mapValues(\.url))
            storageIssue = nil
            return saved
        } catch {
            storageIssue = StorageIssue(message: "无法保存本地历史，操作尚未完成。请检查可用储存空间后重试；原有对话仍已保留。")
            return nil
        }
    }

    private func canEditMessage(_ id: String) -> Bool {
        guard let latest = messages.last(where: { $0.senderRole == .user }),
              latest.id == id,
              latest.purpose == .conversationPractice, latest.revision < Int.max - 1 else { return false }
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
