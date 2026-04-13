import Foundation

// MARK: - ParseEvent

enum ParseEvent: Sendable {
    case total(Int)
    case progress(index: Int, total: Int, percent: Double, fileName: String, crash: CrashLog?)
    case empty
}

// MARK: - CrashParser Protocol

protocol CrashParser: Sendable {
    func canParse(bugType: Int) -> Bool
    func parse(fileName: String, bugType: Int, metadata: [String: Any], metadataRaw: String, body: String, knowledgeBase: KnowledgeBase) -> CrashLog?
}

// MARK: - CrashParserEngine

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

    /// Progressive streaming parser — emits each crash as it's parsed.
    nonisolated func parseDirectoryStream(url: URL) -> AsyncStream<ParseEvent> {
        AsyncStream { continuation in
            Task {
                let fm = FileManager.default
                guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: nil) else {
                    continuation.finish()
                    return
                }

                var ipsFiles: [URL] = []
                while let fileURL = enumerator.nextObject() as? URL {
                    if fileURL.pathExtension.lowercased() == "ips" {
                        ipsFiles.append(fileURL)
                    }
                }

                let total = ipsFiles.count
                guard total > 0 else {
                    continuation.yield(.empty)
                    continuation.finish()
                    return
                }

                continuation.yield(.total(total))

                for (index, fileURL) in ipsFiles.enumerated() {
                    let crash = try? self.parseFile(url: fileURL)
                    let pct = Double(index + 1) / Double(total)
                    continuation.yield(.progress(
                        index: index + 1,
                        total: total,
                        percent: pct,
                        fileName: fileURL.lastPathComponent,
                        crash: crash
                    ))
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Static Helpers

    private static let tsFormatterMs: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SS Z"
        return f
    }()
    private static let tsFormatterSec: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return f
    }()

    static func parseTimestamp(_ str: String?) -> Date? {
        guard let str else { return nil }
        if let d = tsFormatterMs.date(from: str) { return d }
        return tsFormatterSec.date(from: str)
    }

    static func extractMissingSensors(from text: String) -> [String] {
        guard let range = text.range(of: #"Missing sensor\(?s?\)?: ([^\n\\]+)"#, options: .regularExpression) else {
            return []
        }
        let matched = String(text[range])
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
