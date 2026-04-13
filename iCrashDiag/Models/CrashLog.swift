import Foundation
import SwiftUI

enum CrashCategory: String, Codable, CaseIterable, Identifiable {
    case kernelPanic = "Kernel Panic"
    case thermal = "Thermal Event"
    case jetsam = "Jetsam (Memory)"
    case appCrash = "App Crash"
    case gpuEvent = "GPU Event"
    case otaUpdate = "OTA Update"
    case watchdog = "Watchdog Timeout"
    case diskResource = "Disk Resource"
    case unknown = "Unknown"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .kernelPanic: "exclamationmark.triangle.fill"
        case .thermal: "thermometer.sun.fill"
        case .jetsam: "memorychip.fill"
        case .appCrash: "app.badge.fill"
        case .gpuEvent: "rectangle.3.group.fill"
        case .otaUpdate: "arrow.down.circle.fill"
        case .watchdog: "clock.badge.exclamationmark.fill"
        case .diskResource: "externaldrive.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }

    static func from(bugType: Int) -> CrashCategory {
        switch bugType {
        case 210: .kernelPanic
        case 298: .jetsam
        case 308, 309: .appCrash
        case 284: .gpuEvent
        case 183: .otaUpdate
        case 313: .thermal
        case 409: .watchdog
        default: .unknown
        }
    }
}

enum Severity: String, Codable, CaseIterable, Identifiable {
    case critical
    case hardware
    case software
    case informational

    var id: String { rawValue }

    var label: String {
        switch self {
        case .critical: "Critical"
        case .hardware: "Hardware"
        case .software: "Software"
        case .informational: "Info"
        }
    }
}

enum SortOrder: String, CaseIterable {
    case dateDescending = "Newest First"
    case dateAscending = "Oldest First"
    case severity = "Severity"
    case category = "Category"
    case confidence = "Confidence"
}

enum QuickFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case hardware = "Hardware"
    case critical = "Critical"
    case today = "Today"
    case reboots = "Reboots"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .all: "tray.full"
        case .hardware: "wrench.fill"
        case .critical: "exclamationmark.triangle.fill"
        case .today: "clock"
        case .reboots: "arrow.clockwise.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .all: .secondary
        case .hardware: .orange
        case .critical: .red
        case .today: .blue
        case .reboots: .red
        }
    }
}

struct StackFrame: Codable, Sendable {
    let index: Int
    let image: String?
    let address: String?
    let symbol: String?
}

struct CrashLog: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let fileName: String
    let bugType: Int
    let category: CrashCategory
    let timestamp: Date
    let osVersion: String
    let buildVersion: String?
    let deviceModel: String
    let deviceName: String?

    // Panic-specific
    let panicString: String?
    let missingSensors: [String]
    let faultingService: String?
    let cpuCaller: String?

    // App crash-specific
    let processName: String?
    let bundleID: String?
    let exceptionType: String?
    let terminationReason: String?
    let faultingThread: Int?

    // GPU-specific
    let gpuRestartReason: String?
    let gpuSignature: Int?

    // Jetsam-specific
    let largestProcess: String?
    let freePages: Int?
    let activePages: Int?

    // OTA-specific
    let restoreError: Int?

    // Raw
    let rawMetadata: String
    let rawBody: String

    // Diagnosis (set after analysis)
    var diagnosis: Diagnosis?

    /// True if this event forces a full device reboot (kernel panic, watchdog, severe thermal shutdown).
    var isRebootEvent: Bool {
        category == .kernelPanic || category == .watchdog
        || (category == .thermal && (panicString?.lowercased().contains("thermal shutdown") == true
                                      || faultingService?.lowercased() == "critical"))
    }

    static func == (lhs: CrashLog, rhs: CrashLog) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
