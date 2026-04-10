import Foundation

actor KnowledgeBaseManager {
    private let remoteBaseURL: URL
    private let localDir: URL
    private let files = ["version.json", "panic-patterns.json", "iphone-models.json", "components.json"]

    init(repoOwner: String = "ateliersam86", repoName: String = "iCrashDiag") {
        self.remoteBaseURL = URL(string: "https://raw.githubusercontent.com/\(repoOwner)/\(repoName)/main/knowledge/")!
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.localDir = appSupport.appendingPathComponent("iCrashDiag/knowledge")
    }

    func checkForUpdates(currentVersion: String) async -> Bool {
        do {
            let versionURL = remoteBaseURL.appendingPathComponent("version.json")
            let (data, _) = try await URLSession.shared.data(from: versionURL)
            let remote = try JSONDecoder().decode(VersionFile.self, from: data)

            if remote.version > currentVersion {
                try await downloadAll()
                return true
            }
        } catch {
            // Silently fail — use bundled/cached version
        }
        return false
    }

    private func downloadAll() async throws {
        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)

        for file in files {
            let url = remoteBaseURL.appendingPathComponent(file)
            let (data, _) = try await URLSession.shared.data(from: url)
            try data.write(to: localDir.appendingPathComponent(file))
        }
    }
}
