import Foundation

protocol CrashParser: Sendable {
    func canParse(bugType: Int) -> Bool
    func parse(fileName: String, bugType: Int, metadata: [String: Any], metadataRaw: String, body: String, knowledgeBase: KnowledgeBase) -> CrashLog?
}

final class CrashParserEngine: Sendable {
    let parsers: [CrashParser]
    let knowledgeBase: KnowledgeBase

    init(knowledgeBase: KnowledgeBase) {
        self.knowledgeBase = knowledgeBase
        self.parsers = [
            KernelPanicParser(),
            WatchdogParser(),
            JetsamParser(),
            AppCrashParser(),
            GPUEventParser(),
            OTAUpdateParser(),
            ThermalEventParser(),
        ]
    }

    func parseFile(url: URL) throws -> CrashLog? {
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            // Try latin1 for non-UTF8 files
            guard let data = try? Data(contentsOf: url),
                  let str = String(data: data, encoding: .isoLatin1) else { return nil }
            content = str
        }

        guard !content.isEmpty,
              let firstNewline = content.firstIndex(of: "\n") else { return nil }

        let metadataRaw = String(content[content.startIndex..<firstNewline])
        let body = String(content[content.index(after: firstNewline)...])

        guard let metadataData = metadataRaw.data(using: .utf8),
              let metadataObj = try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any] else {
            return nil
        }

        let bugTypeStr = metadataObj["bug_type"] as? String ?? ""
        let bugType = Int(bugTypeStr) ?? 0

        for parser in parsers {
            if parser.canParse(bugType: bugType) {
                return parser.parse(
                    fileName: url.lastPathComponent,
                    bugType: bugType,
                    metadata: metadataObj,
                    metadataRaw: metadataRaw,
                    body: body,
                    knowledgeBase: knowledgeBase
                )
            }
        }

        // Fallback: unknown type
        let timestamp = Self.parseTimestamp(metadataObj["timestamp"] as? String)
        return CrashLog(
            id: UUID(), fileName: url.lastPathComponent, bugType: bugType,
            category: CrashCategory.from(bugType: bugType),
            timestamp: timestamp ?? Date(),
            osVersion: metadataObj["os_version"] as? String ?? "Unknown",
            buildVersion: nil, deviceModel: "Unknown", deviceName: nil,
            panicString: nil, missingSensors: [], faultingService: nil, cpuCaller: nil,
            processName: metadataObj["app_name"] as? String,
            bundleID: nil, exceptionType: nil, terminationReason: nil, faultingThread: nil,
            gpuRestartReason: nil, gpuSignature: nil,
            largestProcess: nil, freePages: nil, activePages: nil,
            restoreError: nil,
            rawMetadata: metadataRaw, rawBody: body, diagnosis: nil
        )
    }

    nonisolated func parseDirectory(url: URL, progress: @Sendable @escaping (Double, String) -> Void) async -> [CrashLog] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: nil) else { return [] }

        var ipsFiles: [URL] = []
        while let fileURL = enumerator.nextObject() as? URL {
            if fileURL.pathExtension.lowercased() == "ips" {
                ipsFiles.append(fileURL)
            }
        }

        let total = ipsFiles.count
        guard total > 0 else { return [] }

        var results: [CrashLog] = []
        for (index, fileURL) in ipsFiles.enumerated() {
            if let crash = try? self.parseFile(url: fileURL) {
                results.append(crash)
            }
            let pct = Double(index + 1) / Double(total)
            progress(pct, "Parsing \(index + 1)/\(total): \(fileURL.lastPathComponent)")
        }
        return results.sorted { $0.timestamp > $1.timestamp }
    }

    static func parseTimestamp(_ str: String?) -> Date? {
        guard let str else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SS Z"
        if let d = formatter.date(from: str) { return d }
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.date(from: str)
    }

    static func extractMissingSensors(from text: String) -> [String] {
        guard let range = text.range(of: #"Missing sensor\(?s?\)?: ([^\n\\]+)"#, options: .regularExpression) else {
            return []
        }
        let matched = String(text[range])
        // Extract the part after the colon
        guard let colonIdx = matched.firstIndex(of: ":") else { return [] }
        let sensorsStr = String(matched[matched.index(after: colonIdx)...])
        return sensorsStr.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func extractFaultingService(from text: String) -> String? {
        guard let range = text.range(of: #"no successful checkins from (\S+)"#, options: .regularExpression) else { return nil }
        let matched = String(text[range])
        let parts = matched.split(separator: " ")
        return parts.last.map(String.init)
    }

    static func extractCPUCaller(from text: String) -> String? {
        guard let range = text.range(of: #"cpu \d+ caller 0x[\da-fA-F]+"#, options: .regularExpression) else { return nil }
        return String(text[range])
    }
}
