import Foundation

/// Persists the last 50 analysis sessions to App Support/iCrashDiag/sessions.json.
final class SessionHistoryStore: Sendable {

    static let shared = SessionHistoryStore()

    private let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("iCrashDiag")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sessions.json")
    }()

    private let maxSessions = 50

    func load() -> [AnalysisSession] {
        guard let data = try? Data(contentsOf: fileURL),
              let sessions = try? JSONDecoder().decode([AnalysisSession].self, from: data)
        else { return [] }
        return sessions
    }

    func save(_ session: AnalysisSession) {
        var all = load()
        all.insert(session, at: 0)
        if all.count > maxSessions { all = Array(all.prefix(maxSessions)) }
        if let data = try? JSONEncoder().encode(all) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func delete(id: UUID) {
        var all = load()
        // Delete stored files on disk if present
        if let session = all.first(where: { $0.id == id }),
           let folderURL = session.storedFolderURL {
            try? FileManager.default.removeItem(at: folderURL)
        }
        all.removeAll { $0.id == id }
        if let data = try? JSONEncoder().encode(all) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Update the storedFolderPath of an existing session (used after a cache is written for an old session)
    func updateStoredPath(id: UUID, path: String) {
        var all = load()
        guard let idx = all.firstIndex(where: { $0.id == id }) else { return }
        all[idx].storedFolderPath = path
        if let data = try? JSONEncoder().encode(all) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Update the sourceFolderPath of an existing session (e.g. after user locates a missing folder)
    func updateSourcePath(id: UUID, path: String) {
        var all = load()
        guard let idx = all.firstIndex(where: { $0.id == id }) else { return }
        all[idx].sourceFolderPath = path
        if let data = try? JSONEncoder().encode(all) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Returns the App Support directory for session file storage
    func sessionStorageURL(for id: UUID) -> URL {
        let base = fileURL.deletingLastPathComponent().appendingPathComponent("sessions")
        let dir = base.appendingPathComponent(id.uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
