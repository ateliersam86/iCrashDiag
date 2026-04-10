import Foundation

/// Persists the last 50 analysis sessions to App Support/iCrashDiag/sessions.json.
final class SessionHistoryStore: Sendable {

    static let shared = SessionHistoryStore()

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("iCrashDiag")
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
            try? data.write(to: fileURL)
        }
    }

    func delete(id: UUID) {
        var all = load()
        all.removeAll { $0.id == id }
        if let data = try? JSONEncoder().encode(all) {
            try? data.write(to: fileURL)
        }
    }
}
