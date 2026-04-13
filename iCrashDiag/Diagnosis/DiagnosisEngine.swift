import Foundation

final class DiagnosisEngine: Sendable {
    let knowledgeBase: KnowledgeBase

    init(knowledgeBase: KnowledgeBase) {
        self.knowledgeBase = knowledgeBase
    }

    func diagnose(crash: CrashLog) -> Diagnosis? {
        var searchText = ""

        // Common fields
        if let ps = crash.panicString { searchText += ps + " " }
        if !crash.missingSensors.isEmpty {
            searchText += "Missing sensor: " + crash.missingSensors.joined(separator: ", ") + " "
        }
        if let fs = crash.faultingService { searchText += fs + " " }
        if let gpr = crash.gpuRestartReason { searchText += gpr + " " }

        // Category-specific enrichment
        switch crash.category {
        case .appCrash:
            if let exc = crash.exceptionType { searchText += exc + " " }
            if let term = crash.terminationReason { searchText += term + " " }
            if let proc = crash.processName { searchText += proc + " " }
        case .jetsam:
            searchText += "JetsamEvent "
            if let reason = crash.faultingService { searchText += reason + " jettisoned " }
        case .gpuEvent:
            searchText += "GPUEvent gpu hang "
            if let proc = crash.processName { searchText += proc + " " }
        case .thermal:
            searchText += "ThermalEvent thermalState "
            if let level = crash.faultingService { searchText += level + " " }
        case .otaUpdate:
            searchText += "OTAEvent "
            if let err = crash.restoreError { searchText += "restore_error Error \(err) " }
            if let stage = crash.faultingService { searchText += stage + " " }
        case .watchdog:
            searchText += "watchdog timeout "
            if let proc = crash.faultingService { searchText += "no successful checkins from \(proc) " }
        case .kernelPanic, .diskResource, .unknown:
            break
        }

        guard !searchText.isEmpty else { return nil }

        let matches = knowledgeBase.findPatterns(in: searchText)
        guard let best = matches.max(by: { $0.confidence < $1.confidence }) else { return nil }

        return Diagnosis(
            patternID: best.id,
            title: best.title,
            severity: Severity(rawValue: best.severity) ?? .informational,
            component: knowledgeBase.component(for: best.component)?.name ?? best.component,
            confidencePercent: best.confidence,
            probabilities: best.probabilities.map { Probability(cause: $0.cause, percent: $0.percent, description: $0.description) },
            repairSteps: best.repairSteps,
            testProcedure: best.testProcedure,
            affectedModels: best.modelsAffected,
            relatedPatterns: best.relatedPatterns
        )
    }

    func analyzeAll(crashes: [CrashLog]) -> AnalysisReport {
        // Skip re-diagnosis for crashes already diagnosed during streaming
        var diagnosedCrashes = crashes.map { crash in
            var c = crash
            if c.diagnosis == nil { c.diagnosis = diagnose(crash: c) }
            return c
        }

        let total = diagnosedCrashes.count
        let dates = diagnosedCrashes.map(\.timestamp).sorted()
        let dateRange: DateRange? = (dates.count >= 2) ? DateRange(start: dates[0], end: dates[dates.count - 1]) : nil

        var deviceModels: [String: Int] = [:]
        for c in diagnosedCrashes {
            let name = c.deviceName ?? c.deviceModel
            deviceModels[name, default: 0] += 1
        }

        var osVersions: [String: Int] = [:]
        for c in diagnosedCrashes { osVersions[c.osVersion, default: 0] += 1 }

        var categoryBreakdown: [String: Int] = [:]
        for c in diagnosedCrashes { categoryBreakdown[c.category.rawValue, default: 0] += 1 }

        var patternCounts: [String: (title: String, count: Int, severity: Severity, component: String)] = [:]
        for c in diagnosedCrashes {
            if let d = c.diagnosis {
                if var existing = patternCounts[d.patternID] {
                    existing.count += 1
                    patternCounts[d.patternID] = existing
                } else {
                    patternCounts[d.patternID] = (d.title, 1, d.severity, d.component)
                }
            }
        }
        let topPatterns = patternCounts.map { key, val in
            PatternFrequency(patternID: key, title: val.title, count: val.count, severity: val.severity, component: val.component)
        }.sorted { $0.count > $1.count }

        var sensorFrequency: [String: Int] = [:]
        for c in diagnosedCrashes {
            for s in c.missingSensors { sensorFrequency[s, default: 0] += 1 }
        }

        var serviceFrequency: [String: Int] = [:]
        for c in diagnosedCrashes {
            if let s = c.faultingService { serviceFrequency[s, default: 0] += 1 }
        }

        var crashesPerDay: [String: Int] = [:]
        for c in diagnosedCrashes { crashesPerDay[Self.dayFormatter.string(from: c.timestamp), default: 0] += 1 }

        let dominant = topPatterns.first.flatMap { top in
            diagnosedCrashes.first(where: { $0.diagnosis?.patternID == top.patternID })?.diagnosis
        }

        let hardwareCount = diagnosedCrashes.filter { $0.diagnosis?.severity == .hardware || $0.diagnosis?.severity == .critical }.count
        let hardwareRatio = total > 0 ? Double(hardwareCount) / Double(total) : 0
        let isHardware = hardwareRatio > 0.3
        let confidence = applyConfidenceModifiers(
            baseConfidence: dominant?.confidencePercent ?? 50,
            totalCrashes: total,
            topPattern: topPatterns.first,
            totalPatterns: topPatterns.count
        )

        let verdictSummary: String
        if let dom = dominant, let top = topPatterns.first {
            verdictSummary = "\(top.count)/\(total) crashes: \(dom.title) — \(dom.component)"
        } else {
            verdictSummary = "No dominant pattern detected across \(total) crashes"
        }

        return AnalysisReport(
            totalCrashes: total,
            dateRange: dateRange,
            deviceModels: deviceModels,
            osVersions: osVersions,
            categoryBreakdown: categoryBreakdown,
            topPatterns: topPatterns,
            sensorFrequency: sensorFrequency,
            serviceFrequency: serviceFrequency,
            crashesPerDay: crashesPerDay,
            dominantDiagnosis: dominant,
            overallVerdict: Verdict(isHardware: isHardware, confidence: confidence, summary: verdictSummary)
        )
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func applyConfidenceModifiers(baseConfidence: Int, totalCrashes: Int, topPattern: PatternFrequency?, totalPatterns: Int) -> Int {
        var confidence = baseConfidence
        if let top = topPattern, top.count >= 10 { confidence += 5 }
        if let top = topPattern, top.count >= 50 { confidence = min(confidence, baseConfidence + 5) }
        if totalPatterns > 3 { confidence -= 10 }
        if totalCrashes == 1 { confidence -= 15 }
        return max(0, min(100, confidence))
    }
}
