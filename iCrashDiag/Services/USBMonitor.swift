import Foundation

/// Polls idevice_id every 3 seconds to detect iPhone connect/disconnect.
/// Notifies via async stream — no IOKit entitlements needed.
actor USBMonitor {
    private var pollingTask: Task<Void, Never>?
    private var lastUDIDs: Set<String> = []

    // Callbacks run on main actor
    private var onConnectedCallback: (@MainActor (String) -> Void)?
    private var onDisconnectedCallback: (@MainActor (String) -> Void)?

    func setCallbacks(
        onConnected: @escaping @MainActor (String) -> Void,
        onDisconnected: @escaping @MainActor (String) -> Void
    ) {
        self.onConnectedCallback = onConnected
        self.onDisconnectedCallback = onDisconnected
    }

    func start(interval: TimeInterval = 3.0) {
        guard pollingTask == nil else { return }
        pollingTask = Task {
            while !Task.isCancelled {
                await poll()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func poll() async {
        let result = await Task.detached(priority: .background) {
            Self.runCommand("idevice_id", args: ["-l"])
        }.value

        let current = Set(
            result
                .split(separator: "\n")
                .map(String.init)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        )

        let connected    = current.subtracting(lastUDIDs)
        let disconnected = lastUDIDs.subtracting(current)
        lastUDIDs = current

        if let cb = onConnectedCallback {
            for udid in connected { await cb(udid) }
        }
        if let cb = onDisconnectedCallback {
            for udid in disconnected { await cb(udid) }
        }
    }

    private static func runCommand(_ command: String, args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = [command] + args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
