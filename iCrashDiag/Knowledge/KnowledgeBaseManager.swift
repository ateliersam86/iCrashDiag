import Foundation

enum KBUpdateResult: Sendable {
    case updated(toVersion: String)
    case alreadyUpToDate
    case failed(String)
}

actor KnowledgeBaseManager {
    private let remoteBaseURL: URL
    private let localDir: URL
    private let files = ["version.json", "panic-patterns.json", "iphone-models.json", "components.json"]

    init(repoOwner: String = "ateliersam86", repoName: String = "iCrashDiag") {
        let rawURL = "https://raw.githubusercontent.com/\(repoOwner)/\(repoName)/main/knowledge/"
        self.remoteBaseURL = URL(string: rawURL) ?? URL(string: "https://raw.githubusercontent.com/ateliersam86/iCrashDiag/main/knowledge/")!
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.localDir = appSupport.appendingPathComponent("iCrashDiag/knowledge")
    }

    /// Convenience: checks and downloads if newer version found. Returns the update result.
    @discardableResult
    func checkAndUpdate() async -> KBUpdateResult {
        let bundleVersion: String
        if let url = Bundle.module.url(forResource: "version", withExtension: "json", subdirectory: "knowledge"),
           let data = try? Data(contentsOf: url),
           let file = try? JSONDecoder().decode(VersionFile.self, from: data) {
            bundleVersion = file.version
        } else { bundleVersion = "0" }
        return await checkForUpdates(currentVersion: bundleVersion)
    }

    @discardableResult
    func checkForUpdates(currentVersion: String) async -> KBUpdateResult {
        do {
            let versionURL = remoteBaseURL.appendingPathComponent("version.json")
            let (data, _) = try await URLSession.shared.data(from: versionURL)
            let remote = try JSONDecoder().decode(VersionFile.self, from: data)

            if remote.version.compare(currentVersion, options: .numeric) == .orderedDescending {
                try await downloadAll()
                return .updated(toVersion: remote.version)
            }
            return .alreadyUpToDate
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func downloadAll() async throws {
        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)

        for file in files {
            let url = remoteBaseURL.appendingPathComponent(file)
            let (data, _) = try await URLSession.shared.data(from: url)
            try data.write(to: localDir.appendingPathComponent(file), options: .atomic)
        }
    }
}
