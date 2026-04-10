import Foundation

struct DeviceInfo: Sendable {
    let udid: String
    let name: String
    let productType: String
    let modelName: String?
    let osVersion: String?
    let buildVersion: String?
    let serialNumber: String?
    let batteryLevel: Int?
    let storageUsed: Int64?
    let storageTotal: Int64?
    let screenshotPath: String?
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
        let nameResult    = run(command: "ideviceinfo", arguments: ["-u", udid, "-k", "DeviceName"])
        let typeResult    = run(command: "ideviceinfo", arguments: ["-u", udid, "-k", "ProductType"])
        let versionResult = run(command: "ideviceinfo", arguments: ["-u", udid, "-k", "ProductVersion"])
        let buildResult   = run(command: "ideviceinfo", arguments: ["-u", udid, "-k", "BuildVersion"])
        let serialResult  = run(command: "ideviceinfo", arguments: ["-u", udid, "-k", "SerialNumber"])

        guard nameResult.exitCode == 0, typeResult.exitCode == 0 else { return nil }

        let battery = batteryLevel(udid: udid)
        let storage = storageInfo(udid: udid)
        let screenshot = captureScreenshot(udid: udid)

        return DeviceInfo(
            udid: udid,
            name: nameResult.output.trimmingCharacters(in: .whitespacesAndNewlines),
            productType: typeResult.output.trimmingCharacters(in: .whitespacesAndNewlines),
            modelName: knowledgeBase.modelName(
                for: typeResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            ),
            osVersion: versionResult.exitCode == 0
                ? versionResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil,
            buildVersion: buildResult.exitCode == 0
                ? buildResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil,
            serialNumber: serialResult.exitCode == 0
                ? serialResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil,
            batteryLevel: battery,
            storageUsed: storage?.used,
            storageTotal: storage?.total,
            screenshotPath: screenshot
        )
    }

    func batteryLevel(udid: String) -> Int? {
        let r = run(command: "ideviceinfo", arguments: ["-u", udid, "-k", "BatteryCurrentCapacity"])
        guard r.exitCode == 0 else { return nil }
        return Int(r.output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func storageInfo(udid: String) -> (used: Int64, total: Int64)? {
        let totalR = run(command: "ideviceinfo", arguments: ["-u", udid, "-k", "TotalDiskCapacity"])
        let availR = run(command: "ideviceinfo", arguments: ["-u", udid, "-k", "TotalSystemAvailable"])
        guard totalR.exitCode == 0,
              let total = Int64(totalR.output.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        let avail = Int64(availR.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        return (total - avail, total)
    }

    func captureScreenshot(udid: String) -> String? {
        let path = "/tmp/icrashdiag_screen_\(udid).png"
        let r = run(command: "idevicescreenshot", arguments: ["-u", udid, path])
        return r.exitCode == 0 ? path : nil
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
