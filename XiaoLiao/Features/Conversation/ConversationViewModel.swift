import Foundation
import Observation

@MainActor
@Observable
final class ConversationViewModel {
    typealias TextAnalyzer = @Sendable (Message) async throws -> MessageTextAnalysis?
    typealias ReplyGenerator = @Sendable (ConversationReplyRequest) async throws -> ConversationReplyResponse
    typealias GrammarEvaluator = @Sendable (GrammarEvaluationRequest) async throws -> GrammarEvaluationResponse
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
    @ObservationIgnored private let textAnalyzer: TextAnalyzer
    @ObservationIgnored private var textAnalysisTask: Task<Void, Never>?
    @ObservationIgnored private var textAnalysisJobs: [Message] = []
    @ObservationIgnored private var queuedTextMessageIDs: Set<String> = []
    @ObservationIgnored private let replyGenerator: ReplyGenerator?
    @ObservationIgnored private var replyTasks: [String: Task<Void, Never>] = [:]
    private(set) var generatingSessionIDs: Set<String> = []
    var replyIssue: String?
    @ObservationIgnored private let grammarEvaluator: GrammarEvaluator?
    @ObservationIgnored private var grammarEvaluationTask: Task<Void, Never>?
    private(set) var activeGrammarRequestIDs: Set<String> = []
    private(set) var grammarStatisticsRevision = 0
    private(set) var grammarQueueIssue: String?

    var pendingGrammarCount: Int { history.reduce(0) { $0 + $1.grammarEvaluationJobs.count } - failedGrammarCount }
    var failedGrammarCount: Int {
        history.flatMap(\.grammarEvaluationJobs).filter {
            $0.state == .failed || ($0.state == .attempted && !activeGrammarRequestIDs.contains($0.id))
        }.count
    }
    var grammarFailureMessage: String? {
        history.flatMap(\.grammarEvaluationJobs).first {
            $0.state == .failed || ($0.state == .attempted && !activeGrammarRequestIDs.contains($0.id))
        }.map { $0.failureMessage ?? "上次语法分析未完成，请重试。" }
    }

    var usesLiveReplies: Bool { replyGenerator != nil }
    var pendingReply: PendingConversationReply? { history.first { $0.id == activeSessionID }?.pendingReply }
    var isGeneratingReply: Bool { activeSessionID.map { generatingSessionIDs.contains($0) } ?? false }
    var canSubmitMessage: Bool { pendingReply == nil }

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
    private(set) var textAnalyses: [MessageTextAnalysis] = []
    @ObservationIgnored private var temporaryRecordings: [String: LocalAudioClip] = [:]
    private(set) var selectedMessageID: String?
    private(set) var editingMessageID: String?
    private(set) var details: [String: Detail] = [:]

    init(history: [ConversationSession]? = nil, audio: ConversationAudioController? = nil,
         textAnalyzer: TextAnalyzer? = nil, replyGenerator: ReplyGenerator? = nil, grammarEvaluator: GrammarEvaluator? = nil) {
        self.history = history ?? MockConversation.history
        self.audio = audio ?? ConversationAudioController()
        self.replyGenerator = replyGenerator
        self.grammarEvaluator = grammarEvaluator
        self.textAnalyzer = textAnalyzer ?? { message in
            try await Task.detached(priority: .utility) { try LocalTextAnalyzer.analyze(message) }.value
        }
        retryPendingTextAnalyses()
        resumeQueuedGrammarEvaluations()
    }

    /// The app opts into disk storage explicitly; tests and previews stay isolated.
    static func persistent(directory: URL? = nil, audio: ConversationAudioController? = nil,
                           textAnalyzer: TextAnalyzer? = nil, replyGenerator: ReplyGenerator? = nil,
                           grammarEvaluator: GrammarEvaluator? = nil) -> ConversationViewModel {
        let model = ConversationViewModel(history: [], audio: audio, textAnalyzer: textAnalyzer,
                                          replyGenerator: replyGenerator, grammarEvaluator: grammarEvaluator)
        model.storageDirectory = directory ?? ConversationHistoryStore.defaultDirectory
        model.retryLoadingHistory()
        return model
    }

    static func persistent(store: ConversationHistoryStore, audio: ConversationAudioController? = nil,
                           textAnalyzer: TextAnalyzer? = nil, replyGenerator: ReplyGenerator? = nil,
                           grammarEvaluator: GrammarEvaluator? = nil) -> ConversationViewModel {
        let model = ConversationViewModel(history: [], audio: audio, textAnalyzer: textAnalyzer,
                                          replyGenerator: replyGenerator, grammarEvaluator: grammarEvaluator)
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
            retryPendingTextAnalyses()
            resumeQueuedGrammarEvaluations()
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
        var session = ConversationSession(
            id: sessionID,
            title: prompt == MockConversation.prompt ? "乌龟" : String(prompt.trimmingCharacters(in: .whitespacesAndNewlines).prefix(12)),
            prompt: prompt,
            messages: usesLiveReplies ? [] : MockConversation.messages(conversationID: sessionID, createdAt: Date()),
            settings: settings
        )
        if usesLiveReplies {
            do { session.pendingReply = .init(request: try ConversationReplyRequest(session: session), failureMessage: nil) }
            catch { replyIssue = error.localizedDescription; return false }
        }
        guard let saved = persist(session) else { return false }
        activeSessionID = nil
        messageVersions = saved.messages
        grammarObservations = saved.grammarObservations
        vocabularyObservations = saved.vocabularyObservations
        textAnalyses = saved.textAnalyses
        resetPresentation()
        history.insert(saved, at: 0)
        activeSessionID = saved.id
        launchReply(in: saved.id)
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
        textAnalyses = session.textAnalyses
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
        textAnalyses = []
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
        guard !text.isEmpty, !audio.hasDraft, canSubmitMessage else { return false }
        if isSystemMessageMode { return submitSystemMessage(text) }
        guard let sessionID = activeSessionID else { return false }
        var updated = messageVersions
        let submitted: Message
        if let id = editingMessageID {
            guard canEditMessage(id), let original = messages.first(where: { $0.id == id }),
                  original.audioAttachment == nil, case .text = original.content else { return false }
            let transcript: Message.Transcription? = original.modality == .spoken ? .init(text: text, confidence: nil) : nil
            submitted = original.edited(content: .text(text), transcription: transcript)
        } else {
            submitted = Message(conversationID: sessionID, senderRole: .user, modality: .written,
                                content: .text(text), replyToMessageID: lastPartnerMessageID)
        }
        updated.append(submitted)
        guard commitTurn(updated, replyingTo: submitted) else { return false }
        if let id = editingMessageID { details[id] = nil }
        audio.stopPlayback()
        draft = ""
        editingMessageID = nil
        selectedMessageID = nil
        enqueueTextAnalysis(submitted)
        launchReply(in: sessionID)
        resumeQueuedGrammarEvaluations()
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
        guard activeSessionID != nil, !audio.hasDraft, !isSystemMessageMode, canSubmitMessage else { return }
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
        guard canSubmitMessage, !isSystemMessageMode, activeSessionID == sessionID, clip.duration.isFinite, clip.duration > 0, clip.duration < Double(Int.max) / 2,
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
        guard activeSessionID != nil, !audio.hasDraft, canSubmitMessage else { return }
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
        if usesLiveReplies {
            guard let sessionID = activeSessionID else { return false }
            let request = Message(conversationID: sessionID, senderRole: .user, purpose: .systemAssistance,
                                  modality: .written, content: .text(text))
            guard commitTurn(messageVersions + [request], replyingTo: request) else { return false }
            draft = ""
            selectedMessageID = nil
            editingMessageID = nil
            endSystemMessageMode()
            launchReply(in: sessionID)
            return true
        }
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
        // Network completions belong to their own conversation, even after navigation.
        guard activeSessionID == saved.id else { return true }
        messageVersions = saved.messages
        grammarObservations = saved.grammarObservations
        vocabularyObservations = saved.vocabularyObservations
        textAnalyses = saved.textAnalyses
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
        session.grammarEvaluationJobs.removeAll { $0.request.messageID == observation.metadata.messageID }
        guard commitSession(session) else { return false }
        grammarStatisticsRevision += 1
        return true
    }

    @discardableResult
    func recordVocabularyObservation(_ observation: VocabularyObservation) -> Bool {
        guard let index = history.firstIndex(where: { $0.id == activeSessionID }) else { return false }
        var session = history[index]
        session.vocabularyObservations.removeAll { $0.metadata.messageID == observation.metadata.messageID }
        session.vocabularyObservations.append(observation)
        return commitSession(session)
    }

    @discardableResult
    func recordTextAnalysis(_ analysis: MessageTextAnalysis) -> Bool {
        guard let index = history.firstIndex(where: { $0.id == activeSessionID }) else { return false }
        var session = history[index]
        session.textAnalyses.removeAll { $0.metadata.messageID == analysis.metadata.messageID }
        session.textAnalyses.append(analysis)
        return commitSession(session)
    }

    /// Retry missing local analyses before capturing a fresh report. Failed
    /// analysis leaves coverage incomplete; it never turns into a fabricated zero.
    func statisticsSnapshot(configuration: StatisticsConfiguration = .init(), interval: DateInterval? = nil,
                            calendar: Calendar = .current) async throws -> StatisticsSnapshot {
        guard storageDirectory == nil || isStorageReady else { throw CocoaError(.fileReadUnknown) }
        retryPendingTextAnalyses()
        await waitForPendingTextAnalyses()
        try Task.checkCancellation()
        guard storageDirectory == nil || isStorageReady else { throw CocoaError(.fileReadUnknown) }
        let sessions = history
        return try await Task.detached(priority: .utility) {
            try StatisticsCalculator.snapshot(sessions: sessions, configuration: configuration,
                                              interval: interval, calendar: calendar)
        }.value
    }

    /// The committed message is the durable work item. A missing result survives
    /// a crash/relaunch without a second job store or migration. Each trigger
    /// attempts an ID at most once; failures wait for a later trigger.
    func retryPendingTextAnalyses() {
        guard storageDirectory == nil || isStorageReady else { return }
        for session in history {
            let analyzedIDs = Set(session.textAnalyses.map { $0.metadata.messageID })
            for message in session.messages where !analyzedIDs.contains(message.id) {
                enqueueTextAnalysis(message)
            }
        }
    }

    /// Also used by focused tests to await the real asynchronous pipeline.
    func waitForPendingTextAnalyses() async {
        while let task = textAnalysisTask { await task.value }
    }

    private func enqueueTextAnalysis(_ message: Message) {
        guard message.countsAsPractice, case .text = message.content,
              !queuedTextMessageIDs.contains(message.id) else { return }
        queuedTextMessageIDs.insert(message.id)
        textAnalysisJobs.append(message)
        guard textAnalysisTask == nil else { return }
        textAnalysisTask = Task { [weak self] in
            guard let self else { return }
            await self.drainTextAnalysisJobs()
        }
    }

    private func drainTextAnalysisJobs() async {
        var next = 0
        while next < textAnalysisJobs.count {
            let message = textAnalysisJobs[next]
            next += 1
            if stillNeedsTextAnalysis(message) {
                do {
                    if let analysis = try await textAnalyzer(message) {
                        saveAutomaticTextAnalysis(analysis, for: message)
                    }
                } catch {
                    // Sending already succeeded. The missing result is retried on
                    // foregrounding, reopening statistics, or the next launch.
                }
            }
            queuedTextMessageIDs.remove(message.id)
        }
        textAnalysisJobs.removeAll(keepingCapacity: false)
        textAnalysisTask = nil
    }

    private func stillNeedsTextAnalysis(_ message: Message) -> Bool {
        guard let session = history.first(where: { $0.id == message.conversationID }) else { return false }
        return session.messages.contains(message) && !session.textAnalyses.contains { $0.metadata.messageID == message.id }
    }

    private func saveAutomaticTextAnalysis(_ analysis: MessageTextAnalysis, for message: Message) {
        guard analysis.metadata.messageID == message.id, analysis.metadata.messageRevision == message.revision,
              analysis.metadata.conversationID == message.conversationID,
              analysis.metadata.textSource == message.statisticsText?.source,
              stillNeedsTextAnalysis(message),
              let index = history.firstIndex(where: { $0.id == message.conversationID }) else { return }
        // Merge into the latest committed session, not the snapshot captured before
        // asynchronous extraction. Never overwrite newer messages/settings/results.
        var session = history[index]
        session.textAnalyses.append(analysis)
        do {
            try session.validate()
            let saved: ConversationSession
            if storageDirectory != nil {
                guard isStorageReady, let historyStore else { return }
                saved = try historyStore.save(session)
            } else {
                saved = session
            }
            history[index] = saved
            if activeSessionID == saved.id { textAnalyses = saved.textAnalyses }
        } catch {
            // Preserve both the submitted message and any existing storage alert.
            // An analysis write failure must not look like a failed chat send.
        }
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
        guard canSubmitMessage, let latest = messages.last(where: { $0.senderRole == .user }),
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
        inputMode = usesLiveReplies ? .text : .voice
        replyIssue = nil
    }
}

extension ConversationViewModel {
    private func commitTurn(_ updated: [Message], replyingTo message: Message) -> Bool {
        guard let index = history.firstIndex(where: { $0.id == activeSessionID }) else { return false }
        var session = history[index]
        session.messages = updated
        session.settings = settings
        do {
            if usesLiveReplies {
                session.pendingReply = .init(request: try ConversationReplyRequest(session: session, replyingTo: message), failureMessage: nil)
            }
        } catch {
            replyIssue = error.localizedDescription
            return false
        }
        if grammarEvaluator != nil, let request = GrammarEvaluationRequest(message: message) {
            session.grammarEvaluationJobs.append(.init(request: request))
        }
        return commitSession(session)
    }

    func retryReply() {
        guard let id = activeSessionID else { return }
        launchReply(in: id)
    }

    /// Cancels the wait after a failure, retaining the already committed learner message.
    func dismissFailedReply() {
        guard !isGeneratingReply, let index = history.firstIndex(where: { $0.id == activeSessionID }) else { return }
        var session = history[index]
        session.pendingReply = nil
        _ = commitSession(session)
    }

    private func launchReply(in sessionID: String) {
        guard let replyGenerator, replyTasks[sessionID] == nil,
              let job = history.first(where: { $0.id == sessionID })?.pendingReply else { return }
        generatingSessionIDs.insert(sessionID)
        replyTasks[sessionID] = Task { [weak self] in
            guard let self else { return }
            defer {
                self.generatingSessionIDs.remove(sessionID)
                self.replyTasks[sessionID] = nil
            }
            do {
                let response = try await replyGenerator(job.request)
                try response.validate(for: job.request)
                self.commitReply(response, for: job.request)
            } catch {
                self.recordReplyFailure(error, for: job.request)
            }
        }
    }

    private func commitReply(_ response: ConversationReplyResponse, for request: ConversationReplyRequest) {
        guard let index = history.firstIndex(where: { $0.id == request.conversationID }),
              history[index].pendingReply?.request == request else { return }
        var session = history[index]
        // A stable result ID plus an atomic message/job save prevents duplicate bubbles.
        guard !session.messages.contains(where: { $0.id == request.requestID }) else { return }
        let message = Message(id: request.requestID, conversationID: session.id,
            senderRole: request.kind == .system ? .system : .aiPartner,
            purpose: request.kind == .system ? .systemAssistance : .conversationPractice,
            modality: .written, content: .text(response.text), replyToMessageID: request.replyToMessageID,
            generation: .init(requestID: request.requestID, model: response.model, promptVersion: response.promptVersion))
        session.messages.append(message)
        session.pendingReply = nil
        if request.kind == .system {
            // Preserve controls changed by the person while the request was in flight.
            if session.settings.tone == request.settings.tone { session.settings.tone = response.settings.tone }
            if session.settings.vocabulary == request.settings.vocabulary { session.settings.vocabulary = response.settings.vocabulary }
            if session.settings.replyLength == request.settings.replyLength { session.settings.replyLength = response.settings.replyLength }
        }
        // On save failure, keep the immutable pending request for explicit retry.
        _ = commitSession(session)
    }

    private func recordReplyFailure(_ error: Error, for request: ConversationReplyRequest) {
        guard let index = history.firstIndex(where: { $0.id == request.conversationID }),
              history[index].pendingReply?.request == request else { return }
        var session = history[index]
        session.pendingReply?.failureMessage = (error as? ConversationReplyError)?.localizedDescription
            ?? ConversationReplyError.unavailable.localizedDescription
        _ = commitSession(session)
    }

    func waitForPendingReplies() async {
        while let task = replyTasks.values.first { await task.value }
    }
}

extension ConversationViewModel {
    /// Only explicitly queued NEW attempts are considered. Missing observations
    /// in older history never turn into an automatic paid backfill.
    func resumeQueuedGrammarEvaluations() {
        guard grammarEvaluator != nil, grammarEvaluationTask == nil,
              storageDirectory == nil || isStorageReady,
              history.contains(where: { $0.grammarEvaluationJobs.contains { $0.state == .queued } }) else { return }
        grammarQueueIssue = nil
        grammarEvaluationTask = Task { [weak self] in
            guard let self else { return }
            await self.drainGrammarEvaluations()
            self.grammarEvaluationTask = nil
        }
    }

    /// Explicit user retry only; attempted/interrupted jobs are not retried on launch.
    func retryFailedGrammarEvaluations() {
        guard grammarEvaluator != nil else { return }
        grammarQueueIssue = nil
        for index in history.indices {
            var session = history[index]
            var changed = false
            for jobIndex in session.grammarEvaluationJobs.indices {
                let job = session.grammarEvaluationJobs[jobIndex]
                if job.state != .queued && !activeGrammarRequestIDs.contains(job.id) {
                    session.grammarEvaluationJobs[jobIndex].state = .queued
                    session.grammarEvaluationJobs[jobIndex].failureMessage = nil
                    changed = true
                }
            }
            if changed && !saveGrammarWork(session) { return }
        }
        resumeQueuedGrammarEvaluations()
    }

    func waitForPendingGrammarEvaluations() async {
        while let task = grammarEvaluationTask { await task.value }
    }

    private func drainGrammarEvaluations() async {
        guard let grammarEvaluator else { return }
        while let job = history.reversed().flatMap(\.grammarEvaluationJobs).first(where: { $0.state == .queued }) {
            guard let index = history.firstIndex(where: { $0.id == job.request.conversationID }),
                  let jobIndex = history[index].grammarEvaluationJobs.firstIndex(where: { $0.id == job.id }) else { break }
            var session = history[index]
            session.grammarEvaluationJobs[jobIndex].state = .attempted
            // Record the attempt BEFORE the paid call. A killed app will offer an
            // explicit retry rather than silently repeat an ambiguous request.
            guard saveGrammarWork(session) else { break }
            activeGrammarRequestIDs.insert(job.id)
            let saved: Bool
            do {
                let response = try await grammarEvaluator(job.request)
                let observation = try response.observation(for: job.request)
                saved = completeGrammarEvaluation(observation, request: job.request)
            } catch {
                saved = failGrammarEvaluation(error, request: job.request)
            }
            activeGrammarRequestIDs.remove(job.id)
            if !saved { break }
        }
    }

    private func completeGrammarEvaluation(_ observation: GrammarObservation, request: GrammarEvaluationRequest) -> Bool {
        guard let index = history.firstIndex(where: { $0.id == request.conversationID }),
              history[index].grammarEvaluationJobs.contains(where: { $0.request == request }),
              let message = history[index].messages.first(where: { $0.id == request.messageID }), request.matches(message) else { return true }
        var session = history[index]
        session.grammarEvaluationJobs.removeAll { $0.id == request.requestID }
        // A manually supplied result wins over any late automatic evaluation.
        if !session.grammarObservations.contains(where: { $0.metadata.messageID == request.messageID }) {
            session.grammarObservations.append(observation)
        }
        guard saveGrammarWork(session) else { return false }
        grammarStatisticsRevision += 1
        return true
    }

    private func failGrammarEvaluation(_ error: Error, request: GrammarEvaluationRequest) -> Bool {
        guard let index = history.firstIndex(where: { $0.id == request.conversationID }),
              let jobIndex = history[index].grammarEvaluationJobs.firstIndex(where: { $0.request == request }) else { return true }
        var session = history[index]
        session.grammarEvaluationJobs[jobIndex].state = .failed
        session.grammarEvaluationJobs[jobIndex].failureMessage = (error as? ConversationReplyError)?.localizedDescription
            ?? "语法分析暂不可用，请稍后重试。"
        return saveGrammarWork(session)
    }

    /// Merge analysis/job state only, without turning a successful send into a
    /// storage error or clearing an unrelated chat/history alert.
    private func saveGrammarWork(_ session: ConversationSession) -> Bool {
        guard let index = history.firstIndex(where: { $0.id == session.id }) else { return false }
        do {
            try session.validate()
            let saved: ConversationSession
            if storageDirectory != nil {
                guard isStorageReady, let historyStore else { throw CocoaError(.fileWriteUnknown) }
                saved = try historyStore.save(session)
            } else { saved = session }
            history[index] = saved
            if activeSessionID == saved.id { grammarObservations = saved.grammarObservations }
            return true
        } catch {
            grammarQueueIssue = "无法保存语法分析进度。消息已保留，请检查储存空间后重试分析。"
            return false
        }
    }
}
