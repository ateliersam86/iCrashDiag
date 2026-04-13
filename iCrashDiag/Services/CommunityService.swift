import Foundation

// MARK: - Share Mode

enum ShareMode: String, CaseIterable {
    case diagnosisOnly = "diagnosisOnly"
    case full = "full"

    var label: String {
        switch self {
        case .diagnosisOnly: return "Diagnosis Only"
        case .full:          return "Full Data"
        }
    }

    var description: String {
        switch self {
        case .diagnosisOnly:
            return "Shares pattern match, confidence score and repair steps. No raw log, no process names."
        case .full:
            return "Shares the anonymized panic string and all crash details alongside the diagnosis."
        }
    }

    var icon: String {
        switch self {
        case .diagnosisOnly: return "lock.shield"
        case .full:          return "doc.text"
        }
    }
}

// MARK: - CommunityService

actor CommunityService {

    static let shared = CommunityService()
    private let baseURL = "https://icrashdiag-license.sam-muselet.workers.dev"

    private init() {}

    // MARK: - Submit Unknown Pattern

    /// Sends an anonymized crash to the server for KB review when confidence < 40 %.
    @discardableResult
    func submitUnknown(_ crash: CrashLog) async -> Bool {
        guard let url = URL(string: "\(baseURL)/submit-unknown") else { return false }

        let keywords = extractPanicKeywords(crash)
        let snippet = anonymizedSnippet(crash)

        var payload: [String: Any] = [
            "category":     crash.category.rawValue,
            "osVersion":    crash.osVersion,
            "deviceModel":  crash.deviceModel,
            "panicKeywords": keywords,
            "confidence":   crash.diagnosis?.confidencePercent ?? 0,
        ]
        if let s = snippet { payload["rawSnippet"] = s }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 10
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Create Share Link

    /// Builds a share payload according to `mode` and posts it, returning a public URL.
    func createShareLink(crash: CrashLog, mode: ShareMode) async throws -> String {
        guard let url = URL(string: "\(baseURL)/share") else {
            throw CommunityError.network
        }

        let data = mode == .full ? fullSharePayload(crash) : diagnosisOnlyPayload(crash)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "mode": mode.rawValue,
            "data": data,
        ])

        let (responseData, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw CommunityError.network }

        if http.statusCode == 503 { throw CommunityError.notConfigured }
        guard http.statusCode == 200 else { throw CommunityError.network }

        let json = (try? JSONSerialization.jsonObject(with: responseData) as? [String: Any])
        guard let shareURL = json?["url"] as? String else { throw CommunityError.network }
        return shareURL
    }

    // MARK: - Feedback

    func submitFeedback(patternID: String, helpful: Bool, crash: CrashLog) async {
        guard let url = URL(string: "\(baseURL)/feedback") else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 8
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "patternId":   patternID,
            "helpful":     helpful,
            "osVersion":   crash.osVersion,
            "deviceModel": crash.deviceModel,
        ])

        _ = try? await URLSession.shared.data(for: req)
    }

    // MARK: - Payload builders

    private func diagnosisOnlyPayload(_ crash: CrashLog) -> [String: Any] {
        var d: [String: Any] = [
            "category":     crash.category.rawValue,
            "osVersion":    majorOSVersion(crash.osVersion),
            "deviceFamily": deviceFamily(crash.deviceModel),
        ]
        if let diag = crash.diagnosis {
            d["diagnosis"] = [
                "patternID":  diag.patternID,
                "title":      diag.title,
                "confidence": diag.confidencePercent,
                "component":  diag.component,
                "severity":   diag.severity.rawValue,
                "probabilities": diag.probabilities.prefix(3).map {
                    ["cause": $0.cause, "percent": $0.percent]
                },
                "repairSteps": diag.repairSteps,
            ]
        }
        return d
    }

    private func fullSharePayload(_ crash: CrashLog) -> [String: Any] {
        var d: [String: Any] = diagnosisOnlyPayload(crash)
        // Full mode: add detailed hardware/crash info but strip personal identifiers
        d["osVersion"] = crash.osVersion   // full version, not just major
        d["deviceModel"] = crash.deviceModel
        d["bugType"] = crash.bugType
        if let ps = crash.panicString { d["panicString"] = ps }
        if !crash.missingSensors.isEmpty { d["missingSensors"] = crash.missingSensors }
        if let fs = crash.faultingService { d["faultingService"] = fs }
        if let exc = crash.exceptionType  { d["exceptionType"] = exc }
        if let term = crash.terminationReason { d["terminationReason"] = term }
        if let gpu = crash.gpuRestartReason   { d["gpuRestartReason"] = gpu }
        if let lp  = crash.largestProcess     { d["largestProcess"] = lp }
        if let fp  = crash.freePages          { d["freePages"] = fp }
        if let err = crash.restoreError       { d["restoreError"] = err }
        // Intentionally excluded: deviceName, bundleID, processName (privacy)
        return d
    }

    // MARK: - Anonymization helpers

    private func extractPanicKeywords(_ crash: CrashLog) -> [String] {
        let source = crash.panicString ?? crash.rawBody
        let words = source
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count > 4 && $0.count < 40 }
            .filter { $0.range(of: #"[A-Za-z_]"#, options: .regularExpression) != nil }
            .filter { !$0.hasPrefix("0x") }
        // Deduplicate and cap at 15
        var seen = Set<String>()
        return words.compactMap { w -> String? in
            let lower = w.lowercased()
                .trimmingCharacters(in: .init(charactersIn: ",:;()[]{}"))
            guard seen.insert(lower).inserted else { return nil }
            return lower
        }.prefix(15).map { $0 }
    }

    private func anonymizedSnippet(_ crash: CrashLog) -> String? {
        guard let raw = crash.panicString ?? (crash.rawBody.isEmpty ? nil : crash.rawBody) else {
            return nil
        }
        // First 400 chars, strip UUIDs and memory addresses
        var snippet = String(raw.prefix(400))
        // Remove UUID patterns
        snippet = snippet.replacingOccurrences(
            of: #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#,
            with: "<uuid>", options: .regularExpression
        )
        // Remove memory addresses
        snippet = snippet.replacingOccurrences(
            of: #"0x[0-9a-fA-F]{6,16}"#,
            with: "<addr>", options: .regularExpression
        )
        return snippet
    }

    private func majorOSVersion(_ version: String) -> String {
        version.components(separatedBy: ".").first ?? version
    }

    private func deviceFamily(_ model: String) -> String {
        // e.g. "iPhone14,3" → "iPhone 14 Pro Max" → we just return the product type family
        if model.hasPrefix("iPhone") { return "iPhone" }
        if model.hasPrefix("iPad")   { return "iPad" }
        if model.hasPrefix("iPod")   { return "iPod touch" }
        return model
    }
}

// MARK: - CommunityError

enum CommunityError: LocalizedError {
    case network
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .network:       return "Could not reach the server. Try again later."
        case .notConfigured: return "Community features are not available yet."
        }
    }
}
