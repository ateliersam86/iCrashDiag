import SwiftUI

/// Centralised persistent settings backed by UserDefaults.
@Observable
@MainActor
final class AppSettings {
    static let shared = AppSettings()

    // MARK: - Appearance
    @ObservationIgnored
    private let defaults = UserDefaults.standard

    var appearanceMode: String {
        didSet { defaults.set(appearanceMode, forKey: "appearanceMode") }
    }

    // MARK: - Language
    var languageCode: String {
        didSet { defaults.set(languageCode, forKey: "languageCode") }
    }

    // MARK: - Knowledge Base
    var autoUpdateKB: Bool {
        didSet { defaults.set(autoUpdateKB, forKey: "autoUpdateKB") }
    }

    // MARK: - Notifications
    var notifyOnDeviceConnect: Bool {
        didSet { defaults.set(notifyOnDeviceConnect, forKey: "notifyOnDeviceConnect") }
    }
    var notifyOnAnalysisComplete: Bool {
        didSet { defaults.set(notifyOnAnalysisComplete, forKey: "notifyOnAnalysisComplete") }
    }

    // MARK: - USB Polling
    var usbPollingEnabled: Bool {
        didSet { defaults.set(usbPollingEnabled, forKey: "usbPollingEnabled") }
    }

    // MARK: - Export
    var exportIncludeRawBody: Bool {
        didSet { defaults.set(exportIncludeRawBody, forKey: "exportIncludeRawBody") }
    }

    // MARK: - What's New
    var lastSeenVersion: String {
        didSet { defaults.set(lastSeenVersion, forKey: "lastSeenVersion") }
    }

    // MARK: - Init

    private init() {
        self.appearanceMode        = defaults.string(forKey: "appearanceMode") ?? "auto"
        self.languageCode          = defaults.string(forKey: "languageCode") ?? "auto"
        self.autoUpdateKB          = defaults.object(forKey: "autoUpdateKB") as? Bool ?? true
        self.notifyOnDeviceConnect = defaults.object(forKey: "notifyOnDeviceConnect") as? Bool ?? true
        self.notifyOnAnalysisComplete = defaults.object(forKey: "notifyOnAnalysisComplete") as? Bool ?? true
        self.usbPollingEnabled     = defaults.object(forKey: "usbPollingEnabled") as? Bool ?? true
        self.exportIncludeRawBody  = defaults.object(forKey: "exportIncludeRawBody") as? Bool ?? false
        self.lastSeenVersion       = defaults.string(forKey: "lastSeenVersion") ?? ""
    }

    // MARK: - Computed

    var colorScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    static let languages: [(code: String, name: String, flag: String)] = [
        ("auto", "System default", "🌐"),
        ("en",   "English",        "🇬🇧"),
        ("fr",   "Français",       "🇫🇷"),
        ("de",   "Deutsch",        "🇩🇪"),
        ("es",   "Español",        "🇪🇸"),
        ("it",   "Italiano",       "🇮🇹"),
        ("pt",   "Português",      "🇵🇹"),
        ("nl",   "Nederlands",     "🇳🇱"),
        ("ja",   "日本語",          "🇯🇵"),
        ("ko",   "한국어",          "🇰🇷"),
        ("zh-Hans", "简体中文",     "🇨🇳"),
        ("zh-Hant", "繁體中文",     "🇹🇼"),
        ("ar",   "العربية",        "🇸🇦"),
    ]
}
