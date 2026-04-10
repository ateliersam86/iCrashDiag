import Foundation

struct JetsamParser: CrashParser {
    func canParse(bugType: Int) -> Bool { bugType == 298 }

    func parse(fileName: String, bugType: Int, metadata: [String: Any], metadataRaw: String, body: String, knowledgeBase: KnowledgeBase) -> CrashLog? {
        let json = (try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any]) ?? [:]

        let timestamp = CrashParserEngine.parseTimestamp(metadata["timestamp"] as? String)
        let memPages = json["memoryPages"] as? [String: Any]
        let largestProc = json["largestProcess"] as? String

        return CrashLog(
            id: UUID(), fileName: fileName, bugType: bugType,
            category: .jetsam, timestamp: timestamp ?? Date(),
            osVersion: metadata["os_version"] as? String ?? "Unknown",
            buildVersion: nil, deviceModel: "Unknown", deviceName: nil,
            panicString: nil, missingSensors: [], faultingService: nil, cpuCaller: nil,
            processName: nil, bundleID: nil, exceptionType: nil, terminationReason: nil, faultingThread: nil,
            gpuRestartReason: nil, gpuSignature: nil,
            largestProcess: largestProc,
            freePages: memPages?["free"] as? Int,
            activePages: memPages?["active"] as? Int,
            restoreError: nil,
            rawMetadata: metadataRaw, rawBody: body, diagnosis: nil
        )
    }
}
