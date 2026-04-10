import Foundation

struct JetsamParser: CrashParser {
    func canParse(bugType: Int) -> Bool { bugType == 298 }

    func parse(fileName: String, bugType: Int, metadata: [String: Any], metadataRaw: String, body: String, knowledgeBase: KnowledgeBase) -> CrashLog? {
        let json = (try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any]) ?? [:]

        let timestamp = CrashParserEngine.parseTimestamp(metadata["timestamp"] as? String)

        let product = json["product"] as? String ?? metadata["device_type"] as? String ?? "Unknown"
        let buildVersion = json["build"] as? String

        // The process killed (typically SpringBoard or the app that exceeded memory)
        let killedProcess = json["name"] as? String

        // Jetsam reason: highwater, per-process-limit, vm-pageshortage, etc.
        let reason = json["reason"] as? String

        // Memory info — try top-level then nested
        let memPages: [String: Any]?
        if let mp = json["memoryPages"] as? [String: Any] {
            memPages = mp
        } else if let sys = json["system"] as? [String: Any] {
            memPages = sys["memoryPages"] as? [String: Any]
        } else {
            memPages = nil
        }

        let freePages = memPages?["free"] as? Int
        let activePages = memPages?["active"] as? Int

        // Largest process
        let largestProcess = json["largestProcess"] as? String
            ?? (json["processes"] as? [[String: Any]])?.max(by: {
                ($0["rpages"] as? Int ?? 0) < ($1["rpages"] as? Int ?? 0)
            })?["name"] as? String

        return CrashLog(
            id: UUID(), fileName: fileName, bugType: bugType,
            category: .jetsam, timestamp: timestamp ?? Date(),
            osVersion: metadata["os_version"] as? String ?? "Unknown",
            buildVersion: buildVersion,
            deviceModel: product,
            deviceName: product == "Unknown" ? nil : knowledgeBase.modelName(for: product),
            panicString: nil, missingSensors: [], faultingService: reason, cpuCaller: nil,
            processName: killedProcess,
            bundleID: nil, exceptionType: nil, terminationReason: nil, faultingThread: nil,
            gpuRestartReason: nil, gpuSignature: nil,
            largestProcess: largestProcess,
            freePages: freePages,
            activePages: activePages,
            restoreError: nil,
            rawMetadata: metadataRaw, rawBody: body, diagnosis: nil
        )
    }
}
