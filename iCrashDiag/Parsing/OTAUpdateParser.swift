import Foundation

struct OTAUpdateParser: CrashParser {
    func canParse(bugType: Int) -> Bool { bugType == 183 }

    func parse(fileName: String, bugType: Int, metadata: [String: Any], metadataRaw: String, body: String, knowledgeBase: KnowledgeBase) -> CrashLog? {
        let timestamp = CrashParserEngine.parseTimestamp(metadata["timestamp"] as? String)
        let restoreError = (metadata["restore_error"] as? String).flatMap(Int.init)

        return CrashLog(
            id: UUID(), fileName: fileName, bugType: bugType,
            category: .otaUpdate, timestamp: timestamp ?? Date(),
            osVersion: metadata["os_version"] as? String ?? metadata["itunes_version"] as? String ?? "Unknown",
            buildVersion: nil, deviceModel: "Unknown", deviceName: nil,
            panicString: nil, missingSensors: [], faultingService: nil, cpuCaller: nil,
            processName: nil, bundleID: nil, exceptionType: nil, terminationReason: nil, faultingThread: nil,
            gpuRestartReason: nil, gpuSignature: nil,
            largestProcess: nil, freePages: nil, activePages: nil,
            restoreError: restoreError,
            rawMetadata: metadataRaw, rawBody: body, diagnosis: nil
        )
    }
}
