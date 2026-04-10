import Foundation

struct AppCrashParser: CrashParser {
    func canParse(bugType: Int) -> Bool { bugType == 308 || bugType == 309 }

    func parse(fileName: String, bugType: Int, metadata: [String: Any], metadataRaw: String, body: String, knowledgeBase: KnowledgeBase) -> CrashLog? {
        let json = (try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any]) ?? [:]

        let timestamp = CrashParserEngine.parseTimestamp(metadata["timestamp"] as? String)
        let exception = json["exception"] as? [String: Any]
        let termination = json["termination"] as? [String: Any]

        return CrashLog(
            id: UUID(), fileName: fileName, bugType: bugType,
            category: .appCrash, timestamp: timestamp ?? Date(),
            osVersion: metadata["os_version"] as? String ?? "Unknown",
            buildVersion: nil, deviceModel: "Unknown", deviceName: nil,
            panicString: nil, missingSensors: [], faultingService: nil, cpuCaller: nil,
            processName: metadata["app_name"] as? String ?? json["procName"] as? String,
            bundleID: metadata["bundleID"] as? String,
            exceptionType: exception?["type"] as? String,
            terminationReason: termination?["indicator"] as? String,
            faultingThread: json["faultingThread"] as? Int,
            gpuRestartReason: nil, gpuSignature: nil,
            largestProcess: nil, freePages: nil, activePages: nil,
            restoreError: nil,
            rawMetadata: metadataRaw, rawBody: body, diagnosis: nil
        )
    }
}
