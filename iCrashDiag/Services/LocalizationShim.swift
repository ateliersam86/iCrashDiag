import Foundation

/// SwiftPM puts .strings files in Bundle.module (iCrashDiag_iCrashDiag.bundle), not Bundle.main.
/// SwiftUI's Text("literal", bundle: .module) resolves via Bundle.main, so it misses our translations.
/// This shim intercepts Bundle.main's localizedString lookup and falls through to Bundle.module.
final class LocalizationBundleShim: Bundle {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        // Try module bundle first (where SwiftPM puts our Localizable.strings)
        let result = Bundle.module.localizedString(forKey: key, value: nil, table: tableName)
        if result != key { return result }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

enum LocalizationShim {
    /// Call once at process start, before any SwiftUI view renders.
    static func install() {
        guard object_getClass(Bundle.main) === Bundle.self else { return }
        object_setClass(Bundle.main, LocalizationBundleShim.self)
    }
}
