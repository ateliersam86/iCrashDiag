import Foundation

struct PatternFrequency: Codable, Identifiable, Sendable {
    var id: String { patternID }
    let patternID: String
    let title: String
    let count: Int
    let severity: Severity
    let component: String
}

struct Verdict: Codable, Sendable {
    let isHardware: Bool
    let confidence: Int
    let summary: String
}

struct DateRange: Codable, Sendable {
    let start: Date
    let end: Date
}

struct AnalysisReport: Codable, Sendable {
    let totalCrashes: Int
    let dateRange: DateRange?
    let deviceModels: [String: Int]
    let osVersions: [String: Int]
    let categoryBreakdown: [String: Int]
    let topPatterns: [PatternFrequency]
    let sensorFrequency: [String: Int]
    let serviceFrequency: [String: Int]
    let crashesPerDay: [String: Int]
    let dominantDiagnosis: Diagnosis?
    let overallVerdict: Verdict
}
