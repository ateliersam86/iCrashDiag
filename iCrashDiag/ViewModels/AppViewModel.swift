import SwiftUI

enum ExportFormat {
    case markdown, json, both
}

@Observable
@MainActor
final class AppViewModel {
    var crashLogs: [CrashLog] = []
    var selectedCrashID: UUID?
    var selectedCategory: CrashCategory?
    var selectedSeverity: Severity?
    var searchText = ""
    var sortOrder: SortOrder = .dateDescending
    var analysisReport: AnalysisReport?
    var isLoading = false
    var loadingProgress: Double = 0
    var loadingMessage = ""
    var usbAvailable = false
    var connectedDevice: DeviceInfo?
    var errorMessage: String?

    let knowledgeBase: KnowledgeBase
    let parserEngine: CrashParserEngine
    let diagnosisEngine: DiagnosisEngine
    let usbService = USBDeviceService()
    let exportService = ExportService()

    init() {
        let kb = KnowledgeBase()
        self.knowledgeBase = kb
        self.parserEngine = CrashParserEngine(knowledgeBase: kb)
        self.diagnosisEngine = DiagnosisEngine(knowledgeBase: kb)
    }

    var filteredCrashLogs: [CrashLog] {
        var logs = crashLogs

        if let cat = selectedCategory {
            logs = logs.filter { $0.category == cat }
        }
        if let sev = selectedSeverity {
            logs = logs.filter { $0.diagnosis?.severity == sev }
        }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            logs = logs.filter { crash in
                crash.fileName.lowercased().contains(query) ||
                crash.category.rawValue.lowercased().contains(query) ||
                (crash.diagnosis?.title.lowercased().contains(query) ?? false) ||
                crash.missingSensors.joined(separator: " ").lowercased().contains(query) ||
                (crash.faultingService?.lowercased().contains(query) ?? false) ||
                (crash.processName?.lowercased().contains(query) ?? false)
            }
        }

        switch sortOrder {
        case .dateDescending: logs.sort { $0.timestamp > $1.timestamp }
        case .dateAscending: logs.sort { $0.timestamp < $1.timestamp }
        case .severity:
            let order: [Severity] = [.critical, .hardware, .software, .informational]
            logs.sort { a, b in
                let ai = order.firstIndex(of: a.diagnosis?.severity ?? .informational) ?? 3
                let bi = order.firstIndex(of: b.diagnosis?.severity ?? .informational) ?? 3
                return ai < bi
            }
        case .category: logs.sort { $0.category.rawValue < $1.category.rawValue }
        }
        return logs
    }

    var selectedCrash: CrashLog? {
        crashLogs.first { $0.id == selectedCrashID }
    }

    var categoryCounters: [(CrashCategory, Int)] {
        var counts: [CrashCategory: Int] = [:]
        for c in crashLogs { counts[c.category, default: 0] += 1 }
        return CrashCategory.allCases.compactMap { cat in
            guard let count = counts[cat], count > 0 else { return nil }
            return (cat, count)
        }
    }

    var severityCounters: [(Severity, Int)] {
        var counts: [Severity: Int] = [:]
        for c in crashLogs {
            let sev = c.diagnosis?.severity ?? .informational
            counts[sev, default: 0] += 1
        }
        return Severity.allCases.compactMap { sev in
            guard let count = counts[sev], count > 0 else { return nil }
            return (sev, count)
        }
    }

    func importFolder(url: URL) async {
        isLoading = true
        loadingMessage = "Scanning for .ips files..."
        loadingProgress = 0

        let engine = parserEngine
        let results = await engine.parseDirectory(url: url) { [weak self] progress, message in
            Task { @MainActor in
                self?.loadingProgress = progress
                self?.loadingMessage = message
            }
        }

        crashLogs = results
        for i in crashLogs.indices {
            crashLogs[i].diagnosis = diagnosisEngine.diagnose(crash: crashLogs[i])
        }
        analysisReport = diagnosisEngine.analyzeAll(crashes: crashLogs)

        isLoading = false
        loadingMessage = "Loaded \(crashLogs.count) crash logs"
    }

    func pullFromUSB() async {
        guard usbService.isAvailable else {
            errorMessage = "libimobiledevice not found. Install with: brew install libimobiledevice"
            return
        }

        let devices = usbService.listDevices()
        guard let udid = devices.first else {
            errorMessage = "No iPhone detected. Connect via USB cable."
            return
        }

        connectedDevice = usbService.deviceInfo(udid: udid, knowledgeBase: knowledgeBase)
        isLoading = true
        loadingMessage = "Extracting crash logs from \(connectedDevice?.name ?? "iPhone")..."

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("iCrashDiag-extract-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let result = usbService.extractCrashLogs(to: tempDir)
        if result.success {
            await importFolder(url: tempDir)
        } else {
            errorMessage = "USB extraction failed: \(result.output)"
            isLoading = false
        }
    }

    func copyReportToClipboard() {
        guard let report = analysisReport else { return }
        let md = exportService.generateMarkdown(crashes: crashLogs, report: report)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)
    }

    func checkUSBAvailability() {
        usbAvailable = usbService.isAvailable
    }
}
