import Foundation

struct OTAUpdateParser: CrashParser {
    func canParse(bugType: Int) -> Bool { bugType == 183 }

    func parse(fileName: String, bugType: Int, metadata: [String: Any], metadataRaw: String, body: String, knowledgeBase: KnowledgeBase) -> CrashLog? {
        let json = (try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any]) ?? [:]

        let timestamp = CrashParserEngine.parseTimestamp(metadata["timestamp"] as? String)
        let restoreError = (metadata["restore_error"] as? String).flatMap(Int.init)
            ?? metadata["restore_error"] as? Int

        let product = json["product"] as? String
            ?? metadata["device_type"] as? String
            ?? "Unknown"

        // Faulting stage/reason during OTA
        let faultingService = json["stage"] as? String
            ?? json["failingPhase"] as? String
            ?? (restoreError != nil ? "Error \(restoreError!)" : nil)

        return CrashLog(
            id: UUID(), fileName: fileName, bugType: bugType,
            category: .otaUpdate, timestamp: timestamp ?? Date(),
            osVersion: metadata["os_version"] as? String
                ?? metadata["itunes_version"] as? String
                ?? json["targetBuild"] as? String
                ?? "Unknown",
            buildVersion: json["build"] as? String
                ?? metadata["build"] as? String,
            deviceModel: product,
            deviceName: product == "Unknown" ? nil : knowledgeBase.modelName(for: product),
            panicString: nil, missingSensors: [], faultingService: faultingService, cpuCaller: nil,
            processName: nil, bundleID: nil, exceptionType: nil, terminationReason: nil, faultingThread: nil,
            gpuRestartReason: nil, gpuSignature: nil,
            largestProcess: nil, freePages: nil, activePages: nil,
            restoreError: restoreError,
            rawMetadata: metadataRaw, rawBody: body, diagnosis: nil
        )
    }
}
