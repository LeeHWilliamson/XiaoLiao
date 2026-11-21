import Foundation

/// Provider-independent wire contract. Audio files and statistics never enter this payload.
nonisolated struct ConversationReplyRequest: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case partner, system }
    struct Turn: Codable, Equatable, Sendable {
        let id: String
        let role: Message.SenderRole
        let purpose: Message.Purpose
        let text: String
    }
    let requestID: String
    let conversationID: String
    let prompt: String
    let settings: ConversationSettings
    let messages: [Turn]
    let replyToMessageID: String?
    let kind: Kind
    let overallPreferences: String?
    let conversationAdjustments: String?
    let explicitSettingKeys: [ConversationSettings.Key]?
    let preferencesVersion: Int?

    init(session: ConversationSession, replyingTo message: Message? = nil, overallPreferences: String = "") throws {
        guard session.prompt.utf16.count <= 4000 else { throw ConversationReplyError.tooLong }
        guard overallPreferences.utf16.count <= 2000, (session.conversationAdjustments?.utf16.count ?? 0) <= 2000 else {
            throw ConversationReplyError.server("Learning preferences or conversation adjustments exceed the 2,000-character limit.")
        }
        self.overallPreferences = overallPreferences
        conversationAdjustments = session.conversationAdjustments ?? ""
        explicitSettingKeys = session.explicitSettingKeys
        preferencesVersion = 1
        requestID = UUID().uuidString
        conversationID = session.id
        prompt = session.prompt
        settings = session.settings
        replyToMessageID = message?.id
        kind = message?.purpose == .systemAssistance ? .system : .partner
        let latestIDs = Set(session.latestMessages.map(\.id))
        // Append order puts an edit after the reply to its original exact version.
        let turns = session.messages.filter { latestIDs.contains($0.id) }.compactMap { record -> Turn? in
            let text: String
            switch record.content {
            case let .text(value): text = value
            case .audio:
                guard let transcript = record.transcription?.text else { return nil }
                text = transcript
            }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return Turn(id: record.id, role: record.senderRole, purpose: record.purpose, text: text)
        }
        if let message {
            guard turns.last?.id == message.id, turns.last!.text.utf16.count <= 4000 else {
                throw ConversationReplyError.tooLong
            }
        }
        // Bounded recent context; never truncate the target message or upload an audio path.
        var selected: [Turn] = []
        var characters = 0
        for turn in turns.reversed() {
            guard selected.count < 40, characters + turn.text.utf16.count <= 24000,
                  turn.text.utf16.count <= 4000 else { break }
            selected.append(turn)
            characters += turn.text.utf16.count
        }
        messages = Array(selected.reversed())
    }
}

nonisolated struct ConversationReplyResponse: Codable, Equatable, Sendable {
    let requestID: String
    let conversationID: String
    let replyToMessageID: String?
    let kind: ConversationReplyRequest.Kind
    let text: String
    let settings: ConversationSettings
    let model: String
    let promptVersion: String
    var conversationAdjustments: String? = ""
    var preferencesVersion: Int? = 1
    var explicitSettingKeys: [ConversationSettings.Key]? = []

    func validate(for request: ConversationReplyRequest) throws {
        if request.preferencesVersion == 1 {
            guard preferencesVersion == 1 else {
                throw ConversationReplyError.server("The AI service needs an update to support learning preferences. Please deploy the latest Worker and retry.")
            }
            guard let conversationAdjustments, conversationAdjustments.utf16.count <= 2000,
                  let explicitSettingKeys, Set(explicitSettingKeys).count == explicitSettingKeys.count,
                  kind == .system || Set(explicitSettingKeys) == Set(request.explicitSettingKeys ?? ConversationSettings.Key.allCases) else {
                throw ConversationReplyError.invalidResponse
            }
        }
        guard (conversationAdjustments?.utf16.count ?? 0) <= 2000,
              request.preferencesVersion == nil || kind == .system || conversationAdjustments == (request.conversationAdjustments ?? ""),
              requestID == request.requestID, conversationID == request.conversationID,
              replyToMessageID == request.replyToMessageID, kind == request.kind,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf16.count <= 6000,
              !model.isEmpty, !promptVersion.isEmpty,
              kind == .system || settings == request.settings else { throw ConversationReplyError.invalidResponse }
    }
}

/// Persist the immutable request, so retries after navigation/relaunch use the SAME ID and body.
nonisolated struct PendingConversationReply: Codable, Equatable, Sendable {
    let request: ConversationReplyRequest
    var failureMessage: String?
}

nonisolated enum ConversationReplyError: Error, LocalizedError, Sendable {
    case notConfigured, tooLong, invalidResponse, unavailable
    case server(String)
    var errorDescription: String? {
        switch self {
        case .notConfigured: "请在设置中输入评分访问码，或联系测试管理员配置 AI 访问。"
        case .tooLong: "主题或消息过长，最多支持 4000 字符。请缩短后重试。"
        case .invalidResponse: "收到的回复无效，请重试。"
        case .unavailable: "网络连接失败或回复超时，请检查网络后重试。"
        case let .server(message): message
        }
    }
}

nonisolated struct ConversationReplyService: Sendable {
    private struct Failure: Decodable, Sendable {
        struct Detail: Decodable, Sendable { let message: String }
        let error: Detail
    }
    let baseURL: URL
    let betaToken: String?
    private let gradingTokenProvider: (@Sendable () throws -> String?)?

    init(baseURL: URL, betaToken: String?, gradingTokenProvider: (@Sendable () throws -> String?)? = nil) {
        self.baseURL = baseURL
        self.betaToken = betaToken
        self.gradingTokenProvider = gradingTokenProvider
    }

    static func configured() -> ConversationReplyService {
        var url = URL(string: "https://xiaoliao-api.leeharriswilliamson.workers.dev")!
        var token: String? = nil
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        token = environment["XIAOLIAO_API_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = environment["XIAOLIAO_API_URL"], let override = URL(string: value),
           override.scheme == "https", override.host != nil, override.user == nil,
           override.password == nil, override.query == nil, override.fragment == nil {
            url = override
        }
        #endif
        // The development credential is never embedded. Graders enter their own
        // separate code; read it per request so a running service sees replacements.
        return ConversationReplyService(baseURL: url, betaToken: token,
                                        gradingTokenProvider: { try GradingCredentialStore().load() })
    }

    func accessCredential() throws -> (token: String, isGrading: Bool) {
        do {
            if let saved = try gradingTokenProvider?() {
                guard (try? GradingAccessCode.normalized(saved)) == saved else { throw GradingAccessError.secureStorage }
                return (saved, true)
            }
        } catch { throw ConversationReplyError.server(GradingAccessError.secureStorage.localizedDescription) }
        guard let betaToken, betaToken.count >= 32 else { throw ConversationReplyError.notConfigured }
        return (betaToken, false)
    }

    func respond(to request: ConversationReplyRequest) async throws -> ConversationReplyResponse {
        let result: ConversationReplyResponse = try await send(request, path: "v1/conversations/respond")
        try result.validate(for: request)
        return result
    }

    func send<Input: Encodable & Sendable, Output: Decodable & Sendable>(_ request: Input, path: String) async throws -> Output {
        let access = try accessCredential()
        var http = URLRequest(url: baseURL.appendingPathComponent(path))
        http.httpMethod = "POST"
        http.timeoutInterval = 50
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.setValue("Bearer \(access.token)", forHTTPHeaderField: "Authorization")
        http.httpBody = try JSONEncoder().encode(request)
        let data: Data
        let response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: http) }
        catch { throw ConversationReplyError.unavailable }
        guard let response = response as? HTTPURLResponse else { throw ConversationReplyError.invalidResponse }
        guard response.statusCode == 200 else {
            if response.statusCode == 401, access.isGrading {
                throw ConversationReplyError.server(GradingAccessError.invalidCode.localizedDescription)
            }
            if let failure = try? JSONDecoder().decode(Failure.self, from: data), failure.error.message.count <= 300 {
                throw ConversationReplyError.server(failure.error.message)
            }
            throw ConversationReplyError.unavailable
        }
        guard let result = try? JSONDecoder().decode(Output.self, from: data) else {
            throw ConversationReplyError.invalidResponse
        }
        return result
    }
}
