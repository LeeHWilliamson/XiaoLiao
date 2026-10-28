import Foundation
import SwiftData

/// One record per conversation: updates never rewrite every saved conversation.
/// Payload versioning is independent of the SwiftData envelope schema.
@Model
nonisolated final class StoredConversation {
    @Attribute(.unique) var id: String
    var position: Int
    var payload: Data

    init(id: String, position: Int, payload: Data) {
        self.id = id
        self.position = position
        self.payload = payload
    }
}

@MainActor
final class ConversationHistoryStore {
    nonisolated private struct Payload: Codable {
        let version: Int
        let session: ConversationSession
    }

    enum StoreError: Error { case unsupportedVersion, invalidSession }

    let directory: URL
    let recordingsDirectory: URL
    private let container: ModelContainer
    private let context: ModelContext
    private let allowsSave: Bool
    private var hasLoaded = false

    init(directory: URL, allowsSave: Bool = true) throws {
        self.directory = directory
        self.allowsSave = allowsSave
        recordingsDirectory = directory.appendingPathComponent("Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        let schema = Schema([StoredConversation.self])
        let configuration = ModelConfiguration(
            "ConversationHistory", schema: schema,
            url: directory.appendingPathComponent("History.store"),
            allowsSave: allowsSave,
            cloudKitDatabase: .none
        )
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("XiaoLiao", isDirectory: true)
            .appendingPathComponent("ConversationData-v2", isDirectory: true)
    }

    func load() throws -> [ConversationSession] {
        hasLoaded = false
        let records = try context.fetch(FetchDescriptor<StoredConversation>(sortBy: [SortDescriptor(\.position, order: .reverse)]))
        let sessions = try records.map { record in
            let session = try decode(record.payload)
            guard session.id == record.id else { throw StoreError.invalidSession }
            return session
        }
        // Never remove files unless every record decoded successfully. Unknown or
        // damaged data is retained for recovery rather than reset to an empty history.
        hasLoaded = true
        if allowsSave { removeOrphanedRecordings(referencedBy: sessions) }
        return sessions
    }

    /// Copy new clips first, then commit metadata. A failed save leaves the old
    /// conversation/audio intact; a crash can at worst leave an unreferenced clip.
    func save(_ session: ConversationSession, recordingSources: [String: URL] = [:]) throws -> ConversationSession {
        guard allowsSave else { throw CocoaError(.fileWriteNoPermission) }
        guard hasLoaded, !session.id.isEmpty,
              Set(session.messages.map(\.id)).count == session.messages.count else { throw StoreError.invalidSession }
        try session.validate()
        var saved = session
        var copiedFiles: [URL] = []
        do {
            var promotedKeys: [String: String] = [:]
            for index in saved.messages.indices {
                guard let attachment = saved.messages[index].audioAttachment else { continue }
                let key = attachment.storageKey
                if let promoted = promotedKeys[key] {
                    saved.messages[index] = saved.messages[index].relocatingAudio(to: promoted)
                } else if let source = recordingSources[key] {
                    let target = recordingsDirectory.appendingPathComponent(UUID().uuidString + ".caf")
                    copiedFiles.append(target)
                    try FileManager.default.copyItem(at: source, to: target)
                    promotedKeys[key] = target.lastPathComponent
                    saved.messages[index] = saved.messages[index].relocatingAudio(to: target.lastPathComponent)
                }
            }
            let payload = try JSONEncoder().encode(Payload(version: 2, session: saved))
            let id = session.id
            var request = FetchDescriptor<StoredConversation>(predicate: #Predicate { $0.id == id })
            request.fetchLimit = 1
            if let record = try context.fetch(request).first {
                record.payload = payload
            } else {
                var newest = FetchDescriptor<StoredConversation>(sortBy: [SortDescriptor(\.position, order: .reverse)])
                newest.fetchLimit = 1
                let position = (try context.fetch(newest).first?.position ?? 0) + 1
                context.insert(StoredConversation(id: session.id, position: position, payload: payload))
            }
            try context.save()
            return saved
        } catch {
            context.rollback()
            for url in copiedFiles { try? FileManager.default.removeItem(at: url) }
            throw error
        }
    }

    func recordingURL(for storageKey: String) -> URL? {
        guard ConversationSession.isRecordingKey(storageKey) else { return nil }
        return recordingsDirectory.appendingPathComponent(storageKey)
    }

    private func decode(_ data: Data) throws -> ConversationSession {
        let decoder = JSONDecoder()
        let payload = try decoder.decode(Payload.self, from: data)
        guard payload.version == 2 else { throw StoreError.unsupportedVersion }
        let session = payload.session
        try session.validate()
        return session
    }

    private func removeOrphanedRecordings(referencedBy sessions: [ConversationSession]) {
        let referenced = Set(sessions.flatMap(\.messages).compactMap { $0.audioAttachment?.storageKey })
        guard let files = try? FileManager.default.contentsOfDirectory(at: recordingsDirectory, includingPropertiesForKeys: nil) else { return }
        for url in files where url.pathExtension == "caf" && !referenced.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
