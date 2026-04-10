import Foundation

struct AppCrashParser: CrashParser {
    func canParse(bugType: Int) -> Bool { bugType == 308 || bugType == 309 }

    func parse(fileName: String, bugType: Int, metadata: [String: Any], metadataRaw: String, body: String, knowledgeBase: KnowledgeBase) -> CrashLog? {
        let json = (try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any]) ?? [:]

        let timestamp = CrashParserEngine.parseTimestamp(metadata["timestamp"] as? String)
        let exception = json["exception"] as? [String: Any]
        let termination = json["termination"] as? [String: Any]

        // Device model — try multiple locations
        let product = json["product"] as? String
            ?? json["modelCode"] as? String
            ?? metadata["device_type"] as? String
            ?? "Unknown"

        // Build version — try nested osVersion object first, then top-level
        let buildVersion: String?
        if let osObj = json["osVersion"] as? [String: Any] {
            buildVersion = osObj["build"] as? String
        } else {
            buildVersion = json["build"] as? String
        }

        // iOS version — prefer the nested object's train string
        let osVersion: String
        if let osObj = json["osVersion"] as? [String: Any],
           let train = osObj["train"] as? String {
            // "iPhone OS 17.0" → "17.0"
            let version = train.replacingOccurrences(of: "iPhone OS ", with: "")
                               .replacingOccurrences(of: "iOS ", with: "")
            osVersion = version.isEmpty ? (metadata["os_version"] as? String ?? "Unknown") : version
        } else {
            osVersion = metadata["os_version"] as? String ?? "Unknown"
        }

        // Process/app name — try multiple keys
        let processName = metadata["app_name"] as? String
            ?? json["procName"] as? String
            ?? json["process"] as? String
            ?? (json["procPath"] as? String).flatMap { URL(fileURLWithPath: $0).lastPathComponent }

        // Bundle ID — try body JSON first, then metadata
        let bundleID = json["bundleID"] as? String
            ?? json["bundleIdentifier"] as? String
            ?? metadata["bundleID"] as? String

        // Exception type + signal
        let exceptionType: String?
        if let excType = exception?["type"] as? String,
           let signal = exception?["signal"] as? String, signal != excType {
            exceptionType = "\(excType) (\(signal))"
        } else {
            exceptionType = exception?["type"] as? String
        }

        // Termination reason — try indicator and namespace together
        let terminationReason: String?
        if let indicator = termination?["indicator"] as? String {
            terminationReason = indicator
        } else if let ns = termination?["namespace"] as? String,
                  let code = termination?["code"] as? Int {
            terminationReason = "\(ns): \(code)"
        } else {
            terminationReason = nil
        }

        return CrashLog(
            id: UUID(), fileName: fileName, bugType: bugType,
            category: .appCrash, timestamp: timestamp ?? Date(),
            osVersion: osVersion,
            buildVersion: buildVersion,
            deviceModel: product,
            deviceName: product == "Unknown" ? nil : knowledgeBase.modelName(for: product),
            panicString: nil, missingSensors: [], faultingService: nil, cpuCaller: nil,
            processName: processName,
            bundleID: bundleID,
            exceptionType: exceptionType,
            terminationReason: terminationReason,
            faultingThread: json["faultingThread"] as? Int,
            gpuRestartReason: nil, gpuSignature: nil,
            largestProcess: nil, freePages: nil, activePages: nil,
            restoreError: nil,
            rawMetadata: metadataRaw, rawBody: body, diagnosis: nil
        )
    }
}
