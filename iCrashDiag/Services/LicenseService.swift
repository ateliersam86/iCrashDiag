import Foundation
import IOKit
import Security

// MARK: - License State

enum LicenseState: Equatable {
    case unknown
    case free
    case pro
    case graceExpired
}

// MARK: - LicenseService

@Observable
@MainActor
final class LicenseService {

    static let shared = LicenseService()

    private(set) var state: LicenseState = .unknown
    private(set) var licenseKey: String? = nil

    private let workerURL = "https://icrashdiag-license.sam-muselet.workers.dev"
    private let keychainService = "com.ateliersam.iCrashDiag.license"
    private let keychainAccount = "licenseKey"
    private let lastValidatedKey = "iCrashDiag.lastValidatedAt"
    private let gracePeriodDays: Double = 7

    var isPro: Bool { state == .pro }

    private init() {}

    // MARK: - Launch validation

    func validateOnLaunch() async {
        let storedKey = readFromKeychain()
        guard let key = storedKey, !key.isEmpty else {
            state = .free
            return
        }
        licenseKey = key

        let deviceId = Self.deviceId()
        do {
            let valid = try await validateWithWorker(key: key, deviceId: deviceId)
            if valid {
                state = .pro
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastValidatedKey)
            } else {
                // Invalid / revoked
                deleteFromKeychain()
                licenseKey = nil
                state = .free
            }
        } catch {
            // Network error — apply grace period
            if isWithinGracePeriod() {
                state = .pro
            } else {
                state = .graceExpired
            }
        }
    }

    // MARK: - Activation

    func activate(key: String) async throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LicenseError.emptyKey }

        let deviceId = Self.deviceId()
        let valid = try await activateWithWorker(key: trimmed, deviceId: deviceId)
        guard valid else { throw LicenseError.invalid }

        saveToKeychain(key: trimmed)
        licenseKey = trimmed
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastValidatedKey)
        state = .pro
    }

    // MARK: - Deactivation

    func deactivate() {
        deleteFromKeychain()
        licenseKey = nil
        state = .free
    }

    // MARK: - Network calls

    private func activateWithWorker(key: String, deviceId: String) async throws -> Bool {
        guard let url = URL(string: "\(workerURL)/activate") else { throw LicenseError.network }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 10
        let body = ["licenseKey": key, "deviceId": deviceId]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw LicenseError.network }

        if http.statusCode == 409 { throw LicenseError.deviceMismatch }
        if http.statusCode == 402 { throw LicenseError.invalid }
        if http.statusCode == 403 { throw LicenseError.revoked }
        if http.statusCode != 200 {
            if let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String {
                throw LicenseError.serverError(msg)
            }
            throw LicenseError.network
        }

        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
        return json?["valid"] as? Bool ?? false
    }

    private func validateWithWorker(key: String, deviceId: String) async throws -> Bool {
        guard let url = URL(string: "\(workerURL)/validate") else { throw LicenseError.network }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 10
        let body = ["licenseKey": key, "deviceId": deviceId]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw LicenseError.network }
        if http.statusCode != 200 { return false }
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
        return json?["valid"] as? Bool ?? false
    }

    // MARK: - Grace period

    private func isWithinGracePeriod() -> Bool {
        let ts = UserDefaults.standard.double(forKey: lastValidatedKey)
        guard ts > 0 else { return false }
        let last = Date(timeIntervalSince1970: ts)
        let elapsed = Date().timeIntervalSince(last)
        return elapsed < gracePeriodDays * 86400
    }

    // MARK: - Device ID

    static func deviceId() -> String {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        defer { IOObjectRelease(service) }
        let uuid = IORegistryEntryCreateCFProperty(
            service,
            "IOPlatformUUID" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String
        return uuid ?? UUID().uuidString
    }

    // MARK: - Keychain

    private func saveToKeychain(key: String) {
        let data = key.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func readFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - LicenseError

enum LicenseError: LocalizedError {
    case emptyKey
    case invalid
    case revoked
    case deviceMismatch
    case network
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .emptyKey: return "Please enter a license key."
        case .invalid: return "License key not found. Check your purchase email."
        case .revoked: return "This license has been revoked."
        case .deviceMismatch: return "License already activated on another Mac."
        case .network: return "Could not reach the license server. Check your internet connection."
        case .serverError(let msg): return "Server error: \(msg)"
        }
    }
}
