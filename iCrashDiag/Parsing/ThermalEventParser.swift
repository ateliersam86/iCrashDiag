import Foundation

struct ThermalEventParser: CrashParser {
    func canParse(bugType: Int) -> Bool { bugType == 313 }

    func parse(fileName: String, bugType: Int, metadata: [String: Any], metadataRaw: String, body: String, knowledgeBase: KnowledgeBase) -> CrashLog? {
        let json = (try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any]) ?? [:]
        let timestamp = CrashParserEngine.parseTimestamp(metadata["timestamp"] as? String)

        let product = json["product"] as? String
            ?? metadata["device_type"] as? String
            ?? "Unknown"

        // Thermal state indicator — e.g. "critical", "fair", "serious"
        let thermalState = json["thermalState"] as? String
            ?? json["thermalLevel"] as? String

        // Top process contributing to heat
        let topProcess = (json["cpuUsage"] as? [[String: Any]])?.first?["name"] as? String
            ?? json["responsiblePID"] as? String

        return CrashLog(
            id: UUID(), fileName: fileName, bugType: bugType,
            category: .thermal, timestamp: timestamp ?? Date(),
            osVersion: metadata["os_version"] as? String ?? "Unknown",
            buildVersion: json["build"] as? String,
            deviceModel: product,
            deviceName: product == "Unknown" ? nil : knowledgeBase.modelName(for: product),
            panicString: json["panicString"] as? String,
            missingSensors: [], faultingService: thermalState, cpuCaller: nil,
            processName: topProcess,
            bundleID: nil, exceptionType: nil, terminationReason: nil, faultingThread: nil,
            gpuRestartReason: nil, gpuSignature: nil,
            largestProcess: nil, freePages: nil, activePages: nil,
            restoreError: nil,
            rawMetadata: metadataRaw, rawBody: body, diagnosis: nil
        )
    }
}
