import Foundation
import XCTest
@testable import XiaoLiao

final class GradingAccessTests: XCTestCase {
    func testCodeNormalizationRejectsHeaderInjectionAndMalformedInput() throws {
        let code = String(repeating: "a", count: 48)
        XCTAssertEqual(try GradingAccessCode.normalized(" \n" + code + "\n "), code)
        for bad in ["", "short", String(repeating: "a", count: 257), code + "\nInjected", code + " bad", String(repeating: "汉", count: 32)] {
            XCTAssertThrowsError(try GradingAccessCode.normalized(bad))
        }
    }

    func testVerifierUsesOnlyTheNonPaidRouteAndRequiresAValidConfirmation() async throws {
        let code = String(repeating: "a", count: 48)
        let service = GradingAccessService(baseURL: URL(string: "https://test.invalid")!) { request in
            XCTAssertEqual(request.url?.path, "/v1/access/check")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer " + code)
            XCTAssertEqual(request.httpBody, Data("{}".utf8))
            XCTAssertEqual(request.timeoutInterval, 20)
            return (Data("{\"status\":\"ok\"}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        try await service.verify(code)
        for (status, body, expected) in [(401, "", GradingAccessError.invalidCode), (403, "", .invalidCode),
                                       (404, "", .outdatedBackend), (503, "", .notConfigured), (429, "", .unavailable),
                                       (200, "{}", .invalidResponse), (200, "{\"status\":\"wrong\"}", .invalidResponse)] {
            let failed = GradingAccessService(baseURL: URL(string: "https://test.invalid")!) { request in
                (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
            }
            do { try await failed.verify(code); XCTFail("Expected validation to fail") }
            catch { XCTAssertEqual(error as? GradingAccessError, expected) }
        }
    }

    @MainActor
    func testVerifiedCodeIsSavedOnceAndAvailableToANewController() async throws {
        let vault = AccessTestVault()
        let code = String(repeating: "a", count: 48)
        let access = makeController(vault)
        access.refresh()
        XCTAssertFalse(access.hasSavedCode)
        access.code = " \n" + code + "\n"
        let task = access.submit()
        await task?.value
        XCTAssertEqual(try vault.load(), code)
        XCTAssertTrue(access.hasSavedCode)
        XCTAssertEqual(access.code, "")
        XCTAssertNil(access.issue)
        XCTAssertFalse(access.isChecking)
        let reopened = makeController(vault)
        reopened.refresh()
        XCTAssertTrue(reopened.hasSavedCode)
        XCTAssertEqual(reopened.code, "") // Stored code is never copied back into the field.
    }

    @MainActor
    func testInvalidCodeAndStorageFailuresPreserveThePreviouslySavedCredential() async throws {
        let old = String(repeating: "a", count: 48)
        let replacement = String(repeating: "b", count: 48)
        let vault = AccessTestVault(old)
        let denied = makeController(vault, verify: { _ in throw GradingAccessError.invalidCode })
        denied.refresh()
        denied.code = replacement
        await denied.submit()?.value
        XCTAssertEqual(try vault.load(), old)
        XCTAssertEqual(denied.code, replacement)
        XCTAssertTrue(denied.hasSavedCode)
        XCTAssertEqual(denied.issue, GradingAccessError.invalidCode.localizedDescription)
        let cannotSave = GradingAccessController(load: { try vault.load() }, save: { _ in throw GradingAccessError.secureStorage },
                                                delete: { try vault.remove() }, verify: { _ in })
        cannotSave.refresh()
        cannotSave.code = replacement
        await cannotSave.submit()?.value
        XCTAssertEqual(cannotSave.issue, GradingAccessError.secureStorage.localizedDescription)
        XCTAssertEqual(try vault.load(), old)
        XCTAssertEqual(cannotSave.code, replacement)
    }

    @MainActor
    func testLeavingDuringValidationCannotSaveALateResultOrDuplicateTheCheck() async throws {
        let started = expectation(description: "Validation started")
        let probe = AccessValidationProbe(onStart: { started.fulfill() })
        let vault = AccessTestVault()
        let access = makeController(vault, verify: { try await probe.verify($0) })
        access.code = String(repeating: "a", count: 48)
        let task = access.submit()
        await fulfillment(of: [started], timeout: 2)
        XCTAssertNil(access.submit())
        access.cancel()
        await probe.release()
        await task?.value
        XCTAssertNil(try vault.load())
        XCTAssertFalse(access.hasSavedCode)
        XCTAssertFalse(access.isChecking)
        XCTAssertEqual(access.code, "")
        XCTAssertNil(access.feedback)
        let calls = await probe.calls
        XCTAssertEqual(calls, 1)
    }

    @MainActor
    func testRemovingDuringAReplacementCheckCannotRestoreTheRemovedCredential() async throws {
        let started = expectation(description: "Replacement check started")
        let probe = AccessValidationProbe(onStart: { started.fulfill() })
        let vault = AccessTestVault(String(repeating: "a", count: 48))
        let access = makeController(vault, verify: { try await probe.verify($0) })
        access.refresh()
        access.code = String(repeating: "b", count: 48)
        let task = access.submit()
        await fulfillment(of: [started], timeout: 2)
        access.remove()
        await probe.release()
        await task?.value
        XCTAssertNil(try vault.load())
        XCTAssertFalse(access.hasSavedCode)
        XCTAssertFalse(access.isChecking)
    }

    func testRunningReplyServiceReadsSavedCredentialsForEveryRequest() throws {
        let developer = String(repeating: "d", count: 48)
        let first = String(repeating: "a", count: 48), second = String(repeating: "b", count: 48)
        let vault = AccessTestVault()
        let service = ConversationReplyService(baseURL: URL(string: "https://test.invalid")!, betaToken: developer,
                                               gradingTokenProvider: { try vault.load() })
        XCTAssertEqual(try service.accessCredential().token, developer)
        XCTAssertFalse(try service.accessCredential().isGrading)
        try vault.save(first)
        XCTAssertEqual(try service.accessCredential().token, first)
        XCTAssertTrue(try service.accessCredential().isGrading)
        try vault.save(second)
        XCTAssertEqual(try service.accessCredential().token, second)
        try vault.remove()
        XCTAssertEqual(try service.accessCredential().token, developer)
        let standalone = ConversationReplyService(baseURL: service.baseURL, betaToken: nil, gradingTokenProvider: { try vault.load() })
        XCTAssertThrowsError(try standalone.accessCredential())
        try vault.save(first)
        XCTAssertEqual(try standalone.accessCredential().token, first)
        let locked = ConversationReplyService(baseURL: service.baseURL, betaToken: developer,
                                              gradingTokenProvider: { throw GradingAccessError.secureStorage })
        XCTAssertThrowsError(try locked.accessCredential())
    }

    @MainActor
    private func makeController(_ vault: AccessTestVault,
                                verify: @escaping @Sendable (String) async throws -> Void = { _ in }) -> GradingAccessController {
        GradingAccessController(load: { try vault.load() }, save: { try vault.save($0) },
                                delete: { try vault.remove() }, verify: verify)
    }
}

/// Injected tests never read or write the user's real Keychain.
nonisolated private final class AccessTestVault: @unchecked Sendable {
    private let lock = NSLock()
    private var code: String?
    init(_ code: String? = nil) { self.code = code }
    func load() throws -> String? { lock.lock(); defer { lock.unlock() }; return code }
    func save(_ value: String) throws { lock.lock(); defer { lock.unlock() }; code = value }
    func remove() throws { lock.lock(); defer { lock.unlock() }; code = nil }
}

private actor AccessValidationProbe {
    private let onStart: @Sendable () -> Void
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var calls = 0
    init(onStart: @escaping @Sendable () -> Void) { self.onStart = onStart }
    func verify(_ code: String) async throws {
        calls += 1
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            onStart()
        }
    }
    func release() { continuation?.resume(); continuation = nil }
}
