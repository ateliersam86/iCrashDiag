import Foundation

struct KernelPanicParser: CrashParser {
    func canParse(bugType: Int) -> Bool { bugType == 210 }

    func parse(fileName: String, bugType: Int, metadata: [String: Any], metadataRaw: String, body: String, knowledgeBase: KnowledgeBase) -> CrashLog? {
        let json = (try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any]) ?? [:]

        let product = json["product"] as? String ?? "Unknown"
        let panicString = json["panicString"] as? String ?? body
        let timestamp = CrashParserEngine.parseTimestamp(metadata["timestamp"] as? String)

        return CrashLog(
            id: UUID(), fileName: fileName, bugType: bugType,
            category: .kernelPanic, timestamp: timestamp ?? Date(),
            osVersion: metadata["os_version"] as? String ?? "Unknown",
            buildVersion: json["build"] as? String,
            deviceModel: product, deviceName: knowledgeBase.modelName(for: product),
            panicString: panicString,
            missingSensors: CrashParserEngine.extractMissingSensors(from: panicString),
            faultingService: CrashParserEngine.extractFaultingService(from: panicString),
            cpuCaller: CrashParserEngine.extractCPUCaller(from: panicString),
            processName: nil, bundleID: nil, exceptionType: nil, terminationReason: nil, faultingThread: nil,
            gpuRestartReason: nil, gpuSignature: nil,
            largestProcess: nil, freePages: nil, activePages: nil,
            restoreError: nil,
            rawMetadata: metadataRaw, rawBody: body, diagnosis: nil
        )
    }
}
