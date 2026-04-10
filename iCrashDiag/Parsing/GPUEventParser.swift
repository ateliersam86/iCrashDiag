import Foundation

struct GPUEventParser: CrashParser {
    func canParse(bugType: Int) -> Bool { bugType == 284 }

    func parse(fileName: String, bugType: Int, metadata: [String: Any], metadataRaw: String, body: String, knowledgeBase: KnowledgeBase) -> CrashLog? {
        let json = (try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any]) ?? [:]

        let timestamp = CrashParserEngine.parseTimestamp(metadata["timestamp"] as? String)
        let analysis = json["analysis"] as? [String: Any]

        return CrashLog(
            id: UUID(), fileName: fileName, bugType: bugType,
            category: .gpuEvent, timestamp: timestamp ?? Date(),
            osVersion: metadata["os_version"] as? String ?? "Unknown",
            buildVersion: nil, deviceModel: "Unknown", deviceName: nil,
            panicString: nil, missingSensors: [], faultingService: nil, cpuCaller: nil,
            processName: metadata["process_name"] as? String ?? json["process_name"] as? String,
            bundleID: nil, exceptionType: nil, terminationReason: nil, faultingThread: nil,
            gpuRestartReason: analysis?["restart_reason_desc"] as? String,
            gpuSignature: analysis?["signature"] as? Int,
            largestProcess: nil, freePages: nil, activePages: nil,
            restoreError: nil,
            rawMetadata: metadataRaw, rawBody: body, diagnosis: nil
        )
    }
}
