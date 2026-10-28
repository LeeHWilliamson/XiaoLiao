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
    func save(_ session: ConversationSession) throws -> ConversationSession {
        guard allowsSave else { throw CocoaError(.fileWriteNoPermission) }
        guard hasLoaded, !session.id.isEmpty,
              Set(session.messages.map(\.id)).count == session.messages.count else { throw StoreError.invalidSession }
        var saved = session
        var copiedFiles: [URL] = []
        do {
            for index in saved.messages.indices {
                guard let clip = saved.messages[index].localAudio else { continue }
                guard clip.duration.isFinite, clip.duration > 0 else { throw StoreError.invalidSession }
                if owns(clip) { continue }
                let target = recordingsDirectory.appendingPathComponent(UUID().uuidString + ".caf")
                copiedFiles.append(target)
                try FileManager.default.copyItem(at: clip.url, to: target)
                saved.messages[index].localAudio = LocalAudioClip(url: target, duration: clip.duration)
            }
            let payload = try JSONEncoder().encode(Payload(version: 1, session: saved))
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

    func owns(_ clip: LocalAudioClip) -> Bool {
        clip.url.standardizedFileURL.deletingLastPathComponent() == recordingsDirectory.standardizedFileURL
    }

    private func decode(_ data: Data) throws -> ConversationSession {
        let decoder = JSONDecoder()
        decoder.userInfo[LocalAudioClip.directoryKey] = recordingsDirectory
        let payload = try decoder.decode(Payload.self, from: data)
        guard payload.version == 1 else { throw StoreError.unsupportedVersion }
        let session = payload.session
        guard !session.id.isEmpty,
              Set(session.messages.map(\.id)).count == session.messages.count else { throw StoreError.invalidSession }
        return session
    }

    private func removeOrphanedRecordings(referencedBy sessions: [ConversationSession]) {
        let referenced = Set(sessions.flatMap(\.messages).compactMap { $0.localAudio?.url.lastPathComponent })
        guard let files = try? FileManager.default.contentsOfDirectory(at: recordingsDirectory, includingPropertiesForKeys: nil) else { return }
        for url in files where url.pathExtension == "caf" && !referenced.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
