import SwiftUI

enum ExportFormat {
    case markdown, json, both
}

enum LoadingStage: Equatable {
    case idle
    case scanning
    case parsing(index: Int, total: Int, file: String)
    case analyzing(done: Int, total: Int)
    case done(count: Int)
}

@Observable
@MainActor
final class AppViewModel {
    var crashLogs: [CrashLog] = [] {
        didSet {
            _categoryCounters = nil
            _severityCounters = nil
        }
    }
    @ObservationIgnored private var _categoryCounters: [(CrashCategory, Int)]? = nil
    @ObservationIgnored private var _severityCounters: [(Severity, Int)]? = nil
    var selectedCrashID: UUID?
    var selectedCategory: CrashCategory?
    var selectedSeverity: Severity?
    var showRebootsOnly: Bool = false
    var quickFilter: QuickFilter = .all
    var searchText = ""
    var sortOrder: SortOrder = .dateDescending
    var analysisReport: AnalysisReport?
    var isLoading = false
    var loadingStage: LoadingStage = .idle
    var usbAvailable = false
    var connectedDevice: DeviceInfo?
    var errorMessage: String?
    var sessionHistory: [AnalysisSession] = []
    var watchedFolderURL: URL?
    var newFilesDetectedCount = 0
    var showLicenseGate = false

    let licenseService = LicenseService.shared

    private let historyStore = SessionHistoryStore.shared
    private let folderWatcher = FolderWatcher()
    nonisolated(unsafe) private var licenseObservers: [any NSObjectProtocol] = []

    // Derived loading values for the view
    var loadingProgress: Double {
        switch loadingStage {
        case .idle, .scanning, .done: return 0
        case .parsing(let i, let t, _): return t > 0 ? Double(i) / Double(t) * 0.9 : 0
        case .analyzing(let d, let t): return t > 0 ? 0.9 + Double(d) / Double(t) * 0.1 : 0.9
        }
    }
    var loadingParsed: Int {
        switch loadingStage {
        case .parsing(let i, _, _): return i
        case .analyzing(let d, _), .done(let d): return d
        default: return 0
        }
    }
    var loadingTotal: Int {
        switch loadingStage {
        case .parsing(_, let t, _), .analyzing(_, let t): return t
        default: return 0
        }
    }
    var loadingCurrentFile: String {
        if case .parsing(_, _, let f) = loadingStage { return f }
        return ""
    }
    var loadingMessage: String {
        switch loadingStage {
        case .idle: return ""
        case .scanning: return "Scanning for .ips files…"
        case .parsing(let i, let t, _): return "\(i) / \(t)"
        case .analyzing: return "Building report…"
        case .done(let c): return "Loaded \(c) crash logs"
        }
    }

    var knowledgeBase: KnowledgeBase
    var parserEngine: CrashParserEngine
    var diagnosisEngine: DiagnosisEngine
    let usbService = USBDeviceService()
    let exportService = ExportService()

    init() {
        let kb = KnowledgeBase()
        self.knowledgeBase = kb
        self.parserEngine = CrashParserEngine(knowledgeBase: kb)
        self.diagnosisEngine = DiagnosisEngine(knowledgeBase: kb)
        self.sessionHistory = historyStore.load()
        // Observer pour l'activation licence
        let activatedToken = NotificationCenter.default.addObserver(
            forName: .licenseActivated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.unlockAllCrashes()
            }
        }
        let deactivatedToken = NotificationCenter.default.addObserver(
            forName: .licenseDeactivated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.relockCrashes()
            }
        }
        licenseObservers = [activatedToken, deactivatedToken]
    }

    deinit {
        licenseObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    var rebootEvents: [CrashLog] {
        crashLogs.filter(\.isRebootEvent).sorted { $0.timestamp > $1.timestamp }
    }

    var rebootCount: Int { rebootEvents.count }

    var filteredCrashLogs: [CrashLog] {
        var logs = crashLogs

        // Quick filter (overrides sidebar filters)
        switch quickFilter {
        case .all: break
        case .hardware: logs = logs.filter { $0.diagnosis?.severity == .hardware }
        case .critical: logs = logs.filter { $0.diagnosis?.severity == .critical }
        case .today:
            let start = Calendar.current.startOfDay(for: Date())
            logs = logs.filter { $0.timestamp >= start }
        case .reboots: logs = logs.filter(\.isRebootEvent)
        }

        // Sidebar filters (only apply when quickFilter == .all)
        if quickFilter == .all {
            if showRebootsOnly { logs = logs.filter(\.isRebootEvent) }
            if let cat = selectedCategory { logs = logs.filter { $0.category == cat } }
            if let sev = selectedSeverity { logs = logs.filter { $0.diagnosis?.severity == sev } }
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
        case .dateAscending:  logs.sort { $0.timestamp < $1.timestamp }
        case .severity:
            let order: [Severity] = [.critical, .hardware, .software, .informational]
            logs.sort { a, b in
                let ai = order.firstIndex(of: a.diagnosis?.severity ?? .informational) ?? 3
                let bi = order.firstIndex(of: b.diagnosis?.severity ?? .informational) ?? 3
                return ai < bi
            }
        case .category: logs.sort { $0.category.rawValue < $1.category.rawValue }
        case .confidence:
            logs.sort { ($0.diagnosis?.confidencePercent ?? 0) > ($1.diagnosis?.confidencePercent ?? 0) }
        }
        return logs
    }

    var selectedCrash: CrashLog? {
        crashLogs.first { $0.id == selectedCrashID }
    }

    var categoryCounters: [(CrashCategory, Int)] {
        if let cached = _categoryCounters { return cached }
        var counts: [CrashCategory: Int] = [:]
        for c in crashLogs { counts[c.category, default: 0] += 1 }
        let result = CrashCategory.allCases.compactMap { cat -> (CrashCategory, Int)? in
            guard let count = counts[cat], count > 0 else { return nil }
            return (cat, count)
        }
        _categoryCounters = result
        return result
    }

    var severityCounters: [(Severity, Int)] {
        if let cached = _severityCounters { return cached }
        var counts: [Severity: Int] = [:]
        for c in crashLogs {
            let sev = c.diagnosis?.severity ?? .informational
            counts[sev, default: 0] += 1
        }
        let result = Severity.allCases.compactMap { sev -> (Severity, Int)? in
            guard let count = counts[sev], count > 0 else { return nil }
            return (sev, count)
        }
        _severityCounters = result
        return result
    }

    // MARK: - Import (Batched Progressive Streaming)

    static let freeFileCap = 10
    // IDs of crash logs locked behind Pro (beyond the 10-file cap)
    private(set) var lockedCrashIDs: Set<UUID> = []

    func isLocked(_ crash: CrashLog) -> Bool {
        !licenseService.isPro && lockedCrashIDs.contains(crash.id)
    }

    var lockedCount: Int { lockedCrashIDs.count }

    func importFolder(url: URL, sourceLabel: String? = nil, saveToHistory: Bool = true) async {
        isLoading = true
        loadingStage = .scanning
        crashLogs = []
        lockedCrashIDs = []
        analysisReport = nil

        let engine = parserEngine
        let diag = diagnosisEngine
        var buffer: [CrashLog] = []
        let batchSize = 20
        var parsedCount = 0

        for await event in engine.parseDirectoryStream(url: url) {
            switch event {
            case .empty:
                break

            case .total(let n):
                loadingStage = .parsing(index: 0, total: n, file: "")

            case .progress(let index, let total, _, let fileName, let crash):
                if index % 5 == 0 || index == total {
                    loadingStage = .parsing(index: index, total: total, file: fileName)
                } else if case .parsing(_, _, _) = loadingStage {
                    loadingStage = .parsing(index: index, total: total, file: loadingCurrentFile)
                }

                if var c = crash {
                    c.diagnosis = diag.diagnose(crash: c)
                    buffer.append(c)
                    parsedCount += 1
                }

                // Flush batch to UI
                let shouldFlush = buffer.count >= batchSize || index == total
                if shouldFlush && !buffer.isEmpty {
                    let batch = buffer
                    buffer = []
                    withAnimation(.easeOut(duration: 0.25)) {
                        crashLogs.append(contentsOf: batch)
                    }
                }
            }
        }

        // Flush any remaining
        if !buffer.isEmpty {
            withAnimation(.easeOut(duration: 0.25)) {
                crashLogs.append(contentsOf: buffer)
            }
        }

        // Analyzing stage — run off main thread then apply
        let total = crashLogs.count
        loadingStage = .analyzing(done: 0, total: total)

        // Lock logs beyond free cap — but report is always computed from ALL logs
        // so the verdict ("hardware issue detected") reflects the true picture.
        // Details of locked logs are hidden behind the paywall in the UI.
        let isPro = licenseService.isPro
        if !isPro && crashLogs.count > Self.freeFileCap {
            lockedCrashIDs = Set(crashLogs.dropFirst(Self.freeFileCap).map(\.id))
        }

        let snapshot = crashLogs
        let report = await Task.detached(priority: .userInitiated) {
            diag.analyzeAll(crashes: snapshot)
        }.value

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            crashLogs.sort { $0.timestamp > $1.timestamp }
            analysisReport = report
        }

        // Re-apply lock order after sort (sort changes dropFirst order)
        if !isPro && crashLogs.count > Self.freeFileCap {
            lockedCrashIDs = Set(crashLogs.dropFirst(Self.freeFileCap).map(\.id))
        }

        loadingStage = .done(count: crashLogs.count)
        isLoading = false

        // Notify analysis complete
        NotificationService.analysisComplete(
            count: crashLogs.count,
            verdict: report.overallVerdict.summary
        )

        // Persist session to history + copy .ips files for later restore
        if !crashLogs.isEmpty && saveToHistory {
            let label = sourceLabel ?? url.lastPathComponent
            let sessionId = UUID()
            let storageURL = historyStore.sessionStorageURL(for: sessionId)

            // Copy source .ips files into App Support session folder
            if let files = try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: nil
            ) {
                for file in files where file.pathExtension == "ips" || file.pathExtension == "log" {
                    let dest = storageURL.appendingPathComponent(file.lastPathComponent)
                    try? FileManager.default.copyItem(at: file, to: dest)
                }
            }

            // Cache parsed results so restore skips re-parsing
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            if let data = try? encoder.encode(crashLogs) {
                try? data.write(to: storageURL.appendingPathComponent("crashlogs.json"), options: .atomic)
            }
            if let reportData = try? encoder.encode(analysisReport) {
                try? reportData.write(to: storageURL.appendingPathComponent("report.json"), options: .atomic)
            }

            let session = AnalysisSession(
                date: .now,
                sourceLabel: label,
                deviceName: connectedDevice?.name,
                deviceModel: connectedDevice?.modelName,
                iosVersion: connectedDevice?.osVersion,
                crashes: crashLogs,
                storedFolderPath: storageURL.path,
                sourceFolderPath: url.path
            )
            historyStore.save(session)
            sessionHistory = historyStore.load()
        }
    }

    /// Restore a previous session — loads from cache if available, re-parses only if needed
    func loadSession(_ session: AnalysisSession) async {
        guard let folderURL = session.storedFolderURL else {
            errorMessage = "Session folder not found. Use \"Locate folder…\" to point to it."
            return
        }
        // Verify the folder actually exists before touching it (avoids macOS privacy prompt crash)
        guard FileManager.default.fileExists(atPath: folderURL.path) else {
            errorMessage = "Folder \"\(folderURL.lastPathComponent)\" is no longer available. Use \"Locate folder…\" to find it."
            return
        }

        let crashCache  = folderURL.appendingPathComponent("crashlogs.json")
        let reportCache = folderURL.appendingPathComponent("report.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        if let cd = try? Data(contentsOf: crashCache),
           let logs = try? decoder.decode([CrashLog].self, from: cd) {
            // Instant restore — apply freemium cap before surfacing anything
            crashLogs = logs
            relockCrashes()

            // Report always covers ALL logs — shows the true verdict.
            // Pro: use cached report (fast path). Free: always recompute from all logs
            // to avoid stale caches that were computed from only the first 10 files.
            if licenseService.isPro,
               let rd = try? Data(contentsOf: reportCache),
               let cachedReport = try? decoder.decode(AnalysisReport.self, from: rd) {
                analysisReport = cachedReport
            } else {
                analysisReport = diagnosisEngine.analyzeAll(crashes: logs)
            }

            selectedCrashID = nil
            sessionHistory = historyStore.load()
            return
        }

        // Fallback: re-parse (old sessions without cache, or corrupted cache)
        await importFolder(url: folderURL, sourceLabel: session.sourceLabel, saveToHistory: false)

        // After re-parse, write cache so next open is instant
        let storageURL = historyStore.sessionStorageURL(for: session.id)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        if let data = try? enc.encode(crashLogs) {
            try? data.write(to: storageURL.appendingPathComponent("crashlogs.json"), options: .atomic)
        }
        if let report = analysisReport, let rd = try? enc.encode(report) {
            try? rd.write(to: storageURL.appendingPathComponent("report.json"), options: .atomic)
        }
        historyStore.updateStoredPath(id: session.id, path: storageURL.path)
        sessionHistory = historyStore.load()
    }

    /// Re-link a grayed-out session to a folder the user located manually
    func locateSession(_ session: AnalysisSession, at url: URL) async {
        historyStore.updateSourcePath(id: session.id, path: url.path)
        sessionHistory = historyStore.load()
        await importFolder(url: url, sourceLabel: session.sourceLabel, saveToHistory: false)

        // Cache results so next open is instant
        let storageURL = historyStore.sessionStorageURL(for: session.id)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        if let data = try? enc.encode(crashLogs) {
            try? data.write(to: storageURL.appendingPathComponent("crashlogs.json"), options: .atomic)
        }
        if let report = analysisReport, let rd = try? enc.encode(report) {
            try? rd.write(to: storageURL.appendingPathComponent("report.json"), options: .atomic)
        }
        historyStore.updateStoredPath(id: session.id, path: storageURL.path)
        sessionHistory = historyStore.load()
    }

    func dismissLicenseGate() {
        showLicenseGate = false
    }

    private func unlockAllCrashes() {
        guard licenseService.isPro else { return }
        lockedCrashIDs = []
        showLicenseGate = false
    }

    private func relockCrashes() {
        guard !licenseService.isPro && crashLogs.count > Self.freeFileCap else { return }
        lockedCrashIDs = Set(crashLogs.dropFirst(Self.freeFileCap).map(\.id))
        showLicenseGate = true
    }

    func deleteSession(id: UUID) {
        historyStore.delete(id: id)
        sessionHistory = historyStore.load()
    }

    // MARK: - Folder watching

    func startWatching(folder: URL) {
        watchedFolderURL = folder
        folderWatcher.start(watching: folder) { [weak self] newURLs in
            guard let self else { return }
            Task { @MainActor in
                self.newFilesDetectedCount += newURLs.count
                await self.importNewFiles(urls: newURLs)
            }
        }
    }

    func stopWatching() {
        folderWatcher.stop()
        watchedFolderURL = nil
    }

    private func importNewFiles(urls: [URL]) async {
        for url in urls {
            guard let crash = try? parserEngine.parseFile(url: url) else { continue }
            var diagnosed = crash
            diagnosed.diagnosis = diagnosisEngine.diagnose(crash: crash)
            withAnimation(.easeOut(duration: 0.2)) {
                crashLogs.append(diagnosed)
            }
        }
        if !crashLogs.isEmpty {
            let snap = crashLogs
            let diag = diagnosisEngine
            let report = await Task.detached(priority: .userInitiated) {
                diag.analyzeAll(crashes: snap)
            }.value
            withAnimation { analysisReport = report }
        }
    }

    /// Import a single .ips file (e.g. double-clicked from Finder or drag-dropped)
    func importSingleIPS(url: URL) async {
        guard let crash = try? parserEngine.parseFile(url: url) else { return }
        var diagnosed = crash
        diagnosed.diagnosis = diagnosisEngine.diagnose(crash: crash)
        withAnimation(.easeOut(duration: 0.2)) {
            crashLogs.append(diagnosed)
            crashLogs.sort { $0.timestamp > $1.timestamp }
        }
        // Enforce freemium cap — prevents bypass via repeated single-file imports
        relockCrashes()
        if !crashLogs.isEmpty {
            // Report always covers all logs — shows true verdict to motivate upgrade
            let snap = crashLogs
            let diag = diagnosisEngine
            let report = await Task.detached(priority: .userInitiated) {
                diag.analyzeAll(crashes: snap)
            }.value
            withAnimation { analysisReport = report }
        }
    }

    // MARK: - USB

    func pullFromUSB() async {
        guard usbService.isAvailable else {
            errorMessage = "libimobiledevice not found. Install: brew install libimobiledevice"
            return
        }
        let devices = usbService.listDevices()
        guard let udid = devices.first else {
            errorMessage = "No iPhone detected. Connect via USB cable."
            return
        }
        let svc = usbService
        let kb = knowledgeBase
        connectedDevice = await Task.detached(priority: .userInitiated) {
            svc.deviceInfo(udid: udid, knowledgeBase: kb)
        }.value
        isLoading = true
        loadingStage = .scanning

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("iCrashDiag-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let result = usbService.extractCrashLogs(to: tempDir)
        if result.success {
            let label = connectedDevice?.name ?? "iPhone (USB)"
            await importFolder(url: tempDir, sourceLabel: label)
        } else {
            errorMessage = "USB extraction failed: \(result.output)"
            isLoading = false
            loadingStage = .idle
        }
    }

    // MARK: - Export

    func copyReportToClipboard() {
        guard licenseService.isPro else { showLicenseGate = true; return }
        guard let report = analysisReport else { return }
        let md = exportService.generateMarkdown(crashes: crashLogs, report: report)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)
    }

    func saveReportAsFile() {
        guard licenseService.isPro else { showLicenseGate = true; return }
        guard let report = analysisReport else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "iCrashDiag-Report.md"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let md = exportService.generateMarkdown(crashes: crashLogs, report: report)
        try? md.write(to: url, atomically: true, encoding: .utf8)
    }

    func exportPDF() {
        guard licenseService.isPro else { showLicenseGate = true; return }
        guard let report = analysisReport else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "iCrashDiag-Report.pdf"
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let html = exportService.generateHTML(crashes: crashLogs, report: report)
        Task { @MainActor in
            do {
                let exporter = PDFExporter()
                let data = try await exporter.export(html: html)
                try data.write(to: url)
            } catch {
                errorMessage = "PDF export failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Sample Logs (demo / onboarding)

    func loadSamples() async {
        guard let samplesURL = Bundle.module.resourceURL?.appendingPathComponent("samples") else { return }
        await importFolder(url: samplesURL, sourceLabel: "Sample Logs")
    }

    // MARK: - USB Availability

    func checkUSBAvailability() {
        usbAvailable = usbService.isAvailable
    }

    // MARK: - Knowledge Base reload

    /// Reloads KnowledgeBase from disk (after an OTA update) without restarting the app.
    /// Also rebuilds parserEngine and diagnosisEngine so new patterns are used immediately.
    func reloadKnowledgeBase() {
        let kb = KnowledgeBase()
        knowledgeBase = kb
        parserEngine = CrashParserEngine(knowledgeBase: kb)
        diagnosisEngine = DiagnosisEngine(knowledgeBase: kb)
    }
}
