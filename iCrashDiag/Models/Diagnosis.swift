import Foundation

struct Diagnosis: Codable, Sendable {
    let patternID: String
    let title: String
    let severity: Severity
    let component: String
    let confidencePercent: Int
    let probabilities: [Probability]
    let repairSteps: [String]
    let testProcedure: [String]
    let affectedModels: [String]
    let relatedPatterns: [String]
}

struct Probability: Codable, Sendable {
    let cause: String
    let percent: Int
    let description: String
}
