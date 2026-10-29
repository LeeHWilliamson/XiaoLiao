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

    init(session: ConversationSession, replyingTo message: Message? = nil) throws {
        guard session.prompt.utf16.count <= 4000 else { throw ConversationReplyError.tooLong }
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

    func validate(for request: ConversationReplyRequest) throws {
        guard requestID == request.requestID, conversationID == request.conversationID,
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
        case .notConfigured: "AI 服务尚未配置，请联系测试管理员。"
        case .tooLong: "主题或消息过长，最多支持 4000 字符。请缩短后重试。"
        case .invalidResponse: "收到的回复无效，请重试。"
        case .unavailable: "网络连接失败或回复超时，请检查网络后重试。"
        case let .server(message): message
        }
    }
}

nonisolated struct ConversationReplyService: Sendable {
    let baseURL: URL
    let betaToken: String?

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
        // This private-beta credential is deliberately not embedded in Release builds.
        return ConversationReplyService(baseURL: url, betaToken: token)
    }

    func respond(to request: ConversationReplyRequest) async throws -> ConversationReplyResponse {
        guard let betaToken, betaToken.count >= 32 else { throw ConversationReplyError.notConfigured }
        var http = URLRequest(url: baseURL.appendingPathComponent("v1/conversations/respond"))
        http.httpMethod = "POST"
        http.timeoutInterval = 50
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.setValue("Bearer \(betaToken)", forHTTPHeaderField: "Authorization")
        http.httpBody = try JSONEncoder().encode(request)
        let data: Data
        let response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: http) }
        catch { throw ConversationReplyError.unavailable }
        guard let response = response as? HTTPURLResponse else { throw ConversationReplyError.invalidResponse }
        guard response.statusCode == 200 else {
            struct Failure: Decodable { struct Detail: Decodable { let message: String }; let error: Detail }
            if let failure = try? JSONDecoder().decode(Failure.self, from: data), failure.error.message.count <= 300 {
                throw ConversationReplyError.server(failure.error.message)
            }
            throw ConversationReplyError.unavailable
        }
        guard let result = try? JSONDecoder().decode(ConversationReplyResponse.self, from: data) else {
            throw ConversationReplyError.invalidResponse
        }
        try result.validate(for: request)
        return result
    }
}
