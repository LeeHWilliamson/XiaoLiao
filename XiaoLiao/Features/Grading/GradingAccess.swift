import Foundation
import Observation
import Security

nonisolated enum GradingAccessError: Error, LocalizedError, Sendable, Equatable {
    case invalidFormat, invalidCode, notConfigured, outdatedBackend, unavailable, invalidResponse, secureStorage

    var errorDescription: String? {
        switch self {
        case .invalidFormat: "请输入管理员提供的完整评分访问码（32–256 个非空格 ASCII 字符）。"
        case .invalidCode: "评分访问码无效或已撤销，请联系测试管理员。"
        case .notConfigured: "评分访问尚未配置，请联系测试管理员。"
        case .outdatedBackend: "评分访问服务尚未部署，请联系测试管理员更新后端。"
        case .unavailable: "无法验证评分访问码，请检查网络后重试。"
        case .invalidResponse: "评分访问验证结果无效，请稍后重试。"
        case .secureStorage: "无法访问安全储存。请解锁设备后重试，访问码尚未更改。"
        }
    }
}

nonisolated enum GradingAccessCode {
    static func normalized(_ value: String) throws -> String {
        let code = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (32...256).contains(code.utf8.count), code.utf8.allSatisfy({ (0x21...0x7e).contains($0) }) else {
            throw GradingAccessError.invalidFormat
        }
        return code
    }
}

/// One device-local, non-synchronizing Keychain item; never UserDefaults/history.
nonisolated struct GradingCredentialStore: Sendable {
    private let service: String

    init() {
        var service = (Bundle.main.bundleIdentifier ?? "XiaoLiao") + ".grading-access"
        #if DEBUG
        if let id = ProcessInfo.processInfo.environment["XIAOLIAO_UI_TEST_STORE"], UUID(uuidString: id) != nil {
            service += ".ui-test." + id
        } else if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            service += ".preview"
        }
        #endif
        self.service = service
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "grading-code", kSecAttrSynchronizable as String: false]
    }

    func load() throws -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let code = String(data: data, encoding: .utf8),
              (try? GradingAccessCode.normalized(code)) == code else { throw GradingAccessError.secureStorage }
        return code
    }

    func save(_ value: String) throws {
        let code = try GradingAccessCode.normalized(value)
        let attributes: [String: Any] = [kSecValueData as String: Data(code.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let item = query.merging(attributes) { _, new in new }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw GradingAccessError.secureStorage }
        } else if status != errSecSuccess { throw GradingAccessError.secureStorage }
    }

    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw GradingAccessError.secureStorage }
    }
}

/// Authentication-only endpoint; no conversation body, AI call or quota charge.
nonisolated struct GradingAccessService: Sendable {
    private struct Confirmation: Decodable, Sendable { let status: String }
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    let baseURL: URL
    private let transport: Transport

    init(baseURL: URL, transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }) {
        self.baseURL = baseURL
        self.transport = transport
    }

    func verify(_ value: String) async throws {
        let code = try GradingAccessCode.normalized(value)
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/access/check"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(code)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("{}".utf8)
        let data: Data, response: URLResponse
        do { (data, response) = try await transport(request) }
        catch { if Task.isCancelled { throw CancellationError() }; throw GradingAccessError.unavailable }
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw GradingAccessError.invalidResponse }
        switch response.statusCode {
        case 200:
            guard let result = try? JSONDecoder().decode(Confirmation.self, from: data), result.status == "ok" else {
                throw GradingAccessError.invalidResponse
            }
        case 401, 403: throw GradingAccessError.invalidCode
        case 404: throw GradingAccessError.outdatedBackend
        case 503: throw GradingAccessError.notConfigured
        default: throw GradingAccessError.unavailable
        }
    }
}

@MainActor
@Observable
final class GradingAccessController {
    var code = ""
    private(set) var hasSavedCode = false
    private(set) var isChecking = false
    private(set) var issue: String?
    private(set) var feedback: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private let load: () throws -> String?
    @ObservationIgnored private let save: (String) throws -> Void
    @ObservationIgnored private let delete: () throws -> Void
    @ObservationIgnored private let verify: @Sendable (String) async throws -> Void

    init(load: (() throws -> String?)? = nil, save: ((String) throws -> Void)? = nil,
         delete: (() throws -> Void)? = nil, verify: (@Sendable (String) async throws -> Void)? = nil) {
        let store = GradingCredentialStore()
        self.load = load ?? { try store.load() }
        self.save = save ?? { try store.save($0) }
        self.delete = delete ?? { try store.remove() }
        var validator: @Sendable (String) async throws -> Void = { code in
            try await GradingAccessService(baseURL: ConversationReplyService.configured().baseURL).verify(code)
        }
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if let id = environment["XIAOLIAO_UI_TEST_STORE"], UUID(uuidString: id) != nil {
            let fixture = environment["XIAOLIAO_UI_TEST_GRADING_ACCESS_FIXTURE"] == "1"
            validator = { code in
                guard fixture, code == "fixture-grading-code-not-real-at-least-32-chars" else { throw GradingAccessError.invalidCode }
            }
        } else if environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            validator = { _ in throw GradingAccessError.notConfigured }
        }
        #endif
        self.verify = verify ?? validator
    }

    func refresh() {
        guard !isChecking else { return }
        do { hasSavedCode = try load() != nil }
        catch { issue = GradingAccessError.secureStorage.localizedDescription }
    }

    @discardableResult
    func submit() -> Task<Void, Never>? {
        guard !isChecking else { return nil }
        let submitted: String
        do { submitted = try GradingAccessCode.normalized(code) }
        catch { issue = GradingAccessError.invalidFormat.localizedDescription; return nil }
        generation = UUID()
        let request = generation
        isChecking = true
        issue = nil
        feedback = nil
        let task = Task { [weak self] in
            guard let self else { return }
            defer { if generation == request { isChecking = false; self.task = nil } }
            do {
                try await verify(submitted)
                guard !Task.isCancelled, generation == request,
                      (try? GradingAccessCode.normalized(code)) == submitted else { return }
                do { try save(submitted) } catch { throw GradingAccessError.secureStorage }
                hasSavedCode = true
                code = ""
                feedback = "评分访问码已安全保存。返回对话后可重试未完成的请求。"
            } catch {
                guard !Task.isCancelled, generation == request else { return }
                issue = (error as? GradingAccessError)?.localizedDescription ?? GradingAccessError.unavailable.localizedDescription
            }
        }
        self.task = task
        return task
    }

    func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        isChecking = false
        code = ""
    }

    func remove() {
        cancel()
        do {
            try delete()
            hasSavedCode = false
            issue = nil
            feedback = "评分访问码已移除。"
        } catch { issue = GradingAccessError.secureStorage.localizedDescription }
    }
}
