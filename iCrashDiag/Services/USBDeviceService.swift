import Foundation

struct DeviceInfo: Sendable {
    let udid: String
    let name: String
    let productType: String
    let modelName: String?
}

final class USBDeviceService: Sendable {

    var isAvailable: Bool {
        let result = run(command: "which", arguments: ["idevicecrashreport"])
        return result.exitCode == 0
    }

    func listDevices() -> [String] {
        let result = run(command: "idevice_id", arguments: ["-l"])
        guard result.exitCode == 0 else { return [] }
        return result.output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    func deviceInfo(udid: String, knowledgeBase: KnowledgeBase) -> DeviceInfo? {
        let nameResult = run(command: "ideviceinfo", arguments: ["-u", udid, "-k", "DeviceName"])
        let typeResult = run(command: "ideviceinfo", arguments: ["-u", udid, "-k", "ProductType"])
        guard nameResult.exitCode == 0, typeResult.exitCode == 0 else { return nil }

        let name = nameResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let productType = typeResult.output.trimmingCharacters(in: .whitespacesAndNewlines)

        return DeviceInfo(
            udid: udid,
            name: name,
            productType: productType,
            modelName: knowledgeBase.modelName(for: productType)
        )
    }

    func extractCrashLogs(to directory: URL) -> (success: Bool, output: String) {
        let result = run(command: "idevicecrashreport", arguments: ["-e", directory.path])
        return (result.exitCode == 0, result.output + result.error)
    }

    private struct ProcessResult: Sendable {
        let exitCode: Int32
        let output: String
        let error: String
    }

    private func run(command: String, arguments: [String]) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ProcessResult(exitCode: -1, output: "", error: error.localizedDescription)
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return ProcessResult(
            exitCode: process.terminationStatus,
            output: String(data: outData, encoding: .utf8) ?? "",
            error: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
