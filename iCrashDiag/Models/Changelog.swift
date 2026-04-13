import SwiftUI

// MARK: - Data model

struct ChangelogEntry {
    let version: String
    let date: String
    let items: [ChangelogItem]
}

struct ChangelogItem {
    let icon: String
    let color: Color
    let title: String
    let detail: String
}

// MARK: - Registry (add a new entry here with every release)

enum Changelog {

    static let entries: [ChangelogEntry] = [

        ChangelogEntry(version: "1.3.1", date: "April 2026", items: [
            ChangelogItem(icon: "checkmark.seal",           color: .green,  title: "Verdict on all logs",       detail: "The overall diagnosis now covers every crash log — free users see the real severity even before upgrading."),
            ChangelogItem(icon: "bell.badge",               color: .orange, title: "Notifications onboarding",  detail: "Permission request now happens inside the app, after the window opens — no more system dialog at startup."),
            ChangelogItem(icon: "folder.badge.minus",       color: .red,    title: "No Desktop folder prompt",  detail: "Fixed a macOS privacy dialog appearing before the main window when the resource bundle was missing from the app package."),
        ]),

        ChangelogEntry(version: "1.3.0", date: "April 2026", items: [
            ChangelogItem(icon: "gearshape",             color: .orange, title: "Settings button",           detail: "The ⚙ toolbar button now reliably opens the Settings window via ⌘,."),
            ChangelogItem(icon: "globe",                 color: .blue,   title: "Language auto-detection",   detail: "App follows macOS system language automatically (French, English…)."),
            ChangelogItem(icon: "clock.arrow.circlepath",color: .purple, title: "Instant session restore",   detail: "Previously analysed sessions load from cache — no full re-parse on re-open."),
            ChangelogItem(icon: "brain.head.profile",    color: .teal,   title: "Live KB reload",            detail: "Knowledge base updates apply immediately in the current session without restarting."),
            ChangelogItem(icon: "tag",                   color: .indigo, title: "Incremental versioning",    detail: "Proper v1.x.y release tags on GitHub. Version shown dynamically in About."),
        ]),

        ChangelogEntry(version: "1.2.0", date: "April 2026", items: [
            ChangelogItem(icon: "shield.lefthalf.filled",color: .red,    title: "Security hardening",        detail: "Grace period moved to Keychain. Force-unwrap crash risks eliminated across the codebase."),
            ChangelogItem(icon: "brain",                 color: .teal,   title: "267 diagnostic patterns",   detail: "Knowledge base expanded with XNU source patterns; 19 duplicates removed."),
            ChangelogItem(icon: "checkmark.seal",        color: .orange, title: "Crash fixes",               detail: "Eliminated force-unwrap crashes on URL init, date ranges, and export paths."),
        ]),

        ChangelogEntry(version: "1.1.0", date: "March 2026", items: [
            ChangelogItem(icon: "key.fill",              color: .orange, title: "Pro license system",        detail: "Gumroad + Cloudflare Worker backend with 7-day grace period and per-device locking."),
            ChangelogItem(icon: "lock.open",             color: .green,  title: "Freemium gate",             detail: "First 50 crash logs free. Pro unlocks unlimited analysis and exports."),
            ChangelogItem(icon: "iphone.gen3",           color: .blue,   title: "Device dashboard",          detail: "Connected iPhone details: model name, serial, iOS version, storage."),
            ChangelogItem(icon: "line.3.horizontal.decrease.circle", color: .purple, title: "Quick filters", detail: "Filter by category, severity, and free-text search in real-time."),
        ]),

        ChangelogEntry(version: "1.0.0", date: "March 2026", items: [
            ChangelogItem(icon: "stethoscope",           color: .orange, title: "iCrashDiag 1.0",            detail: "Native macOS crash log analyser for iPhone repair technicians."),
            ChangelogItem(icon: "doc.text.magnifyingglass",color: .blue, title: "Diagnostic patterns",       detail: "Kernel panics, watchdogs, sensors, GPU, NAND, audio IC, Face ID and more."),
            ChangelogItem(icon: "chart.bar.doc.horizontal",color: .purple, title: "Progressive analysis",   detail: "Real-time parsing with hardware vs software verdict and confidence score."),
            ChangelogItem(icon: "iphone.gen3",           color: .green,  title: "USB extraction",            detail: "Pull crash logs directly from a connected iPhone via libimobiledevice."),
            ChangelogItem(icon: "square.and.arrow.up",   color: .indigo, title: "Export Markdown & JSON",    detail: "Full diagnosis report for clipboard, file, or AI analysis tools."),
            ChangelogItem(icon: "arrow.clockwise.icloud",color: .teal,   title: "Auto-updating KB",          detail: "New iPhone models and patterns fetched from GitHub without an app update."),
        ]),
    ]

    /// Entry matching the running app version, or the most recent entry as fallback.
    static var current: ChangelogEntry {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        return entries.first { $0.version == version } ?? entries[0]
    }
}
