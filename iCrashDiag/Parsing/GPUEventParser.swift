import Foundation

struct GPUEventParser: CrashParser {
    func canParse(bugType: Int) -> Bool { bugType == 284 }

    func parse(fileName: String, bugType: Int, metadata: [String: Any], metadataRaw: String, body: String, knowledgeBase: KnowledgeBase) -> CrashLog? {
        let json = (try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any]) ?? [:]

        let timestamp = CrashParserEngine.parseTimestamp(metadata["timestamp"] as? String)
        let analysis = json["analysis"] as? [String: Any]

        let product = json["product"] as? String
            ?? json["deviceType"] as? String
            ?? metadata["device_type"] as? String
            ?? "Unknown"

        // GPU process name — the app using the GPU when it reset
        let processName = analysis?["process_name"] as? String
            ?? json["process_name"] as? String
            ?? metadata["process_name"] as? String
            ?? metadata["app_name"] as? String

        return CrashLog(
            id: UUID(), fileName: fileName, bugType: bugType,
            category: .gpuEvent, timestamp: timestamp ?? Date(),
            osVersion: metadata["os_version"] as? String ?? "Unknown",
            buildVersion: json["build"] as? String,
            deviceModel: product,
            deviceName: product == "Unknown" ? nil : knowledgeBase.modelName(for: product),
            panicString: nil, missingSensors: [], faultingService: nil, cpuCaller: nil,
            processName: processName,
            bundleID: nil, exceptionType: nil, terminationReason: nil, faultingThread: nil,
            gpuRestartReason: analysis?["restart_reason_desc"] as? String
                ?? json["gpuRestartReason"] as? String,
            gpuSignature: analysis?["signature"] as? Int
                ?? json["gpuSignature"] as? Int,
            largestProcess: nil, freePages: nil, activePages: nil,
            restoreError: nil,
            rawMetadata: metadataRaw, rawBody: body, diagnosis: nil
        )
    }
}
