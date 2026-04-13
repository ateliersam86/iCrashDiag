import Foundation

struct AnalysisSession: Identifiable, Codable, Sendable {
    let id: UUID
    let date: Date
    let sourceLabel: String       // folder name or device name
    let deviceName: String?       // USB device user-visible name
    let deviceModel: String?      // "iPhone SE (2nd gen)"
    let iosVersion: String?
    let crashCount: Int
    let criticalCount: Int
    let hardwareCount: Int
    let softwareCount: Int
    let topCategory: CrashCategory?
    /// Path to ~/Library/Application Support/iCrashDiag/sessions/{uuid}/ — nil for old sessions
    var storedFolderPath: String?
    /// Original source folder path (fallback when storedFolderPath doesn't exist)
    var sourceFolderPath: String?

    /// Best available URL to restore from: App Support copy first, original source as fallback
    var restorableURL: URL? {
        let fm = FileManager.default
        if let p = storedFolderPath {
            let url = URL(fileURLWithPath: p)
            if fm.fileExists(atPath: p) { return url }
        }
        if let p = sourceFolderPath {
            let url = URL(fileURLWithPath: p)
            if fm.fileExists(atPath: p) { return url }
        }
        return nil
    }

    // Keep backward compat
    var storedFolderURL: URL? { restorableURL }

    var isRestorable: Bool { restorableURL != nil }

    init(
        date: Date = .now,
        sourceLabel: String,
        deviceName: String? = nil,
        deviceModel: String? = nil,
        iosVersion: String? = nil,
        crashes: [CrashLog],
        storedFolderPath: String? = nil,
        sourceFolderPath: String? = nil
    ) {
        self.id = UUID()
        self.date = date
        self.sourceLabel = sourceLabel
        self.deviceName = deviceName
        self.deviceModel = deviceModel
        self.iosVersion = iosVersion
        self.storedFolderPath = storedFolderPath
        self.sourceFolderPath = sourceFolderPath
        self.crashCount = crashes.count
        self.criticalCount  = crashes.filter { $0.diagnosis?.severity == .critical }.count
        self.hardwareCount  = crashes.filter { $0.diagnosis?.severity == .hardware }.count
        self.softwareCount  = crashes.filter { $0.diagnosis?.severity == .software }.count

        // Most frequent category
        var counts: [CrashCategory: Int] = [:]
        for c in crashes { counts[c.category, default: 0] += 1 }
        self.topCategory = counts.max(by: { $0.value < $1.value })?.key
    }

    var severitySummary: String {
        var parts: [String] = []
        if criticalCount > 0 { parts.append("\(criticalCount) critical") }
        if hardwareCount > 0 { parts.append("\(hardwareCount) hardware") }
        if softwareCount > 0 { parts.append("\(softwareCount) software") }
        return parts.isEmpty ? "\(crashCount) logs" : parts.joined(separator: ", ")
    }
}
