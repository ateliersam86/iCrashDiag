import Foundation

struct PatternDefinition: Codable, Sendable {
    let id: String
    let keywords: [String]
    let category: String
    let component: String
    let severity: String
    let confidence: Int
    let title: String
    let diagnosis: String
    let probabilities: [ProbabilityDefinition]
    let repairSteps: [String]
    let testProcedure: [String]
    let modelsAffected: [String]
    let relatedPatterns: [String]

    enum CodingKeys: String, CodingKey {
        case id, keywords, category, component, severity, confidence, title, diagnosis, probabilities
        case repairSteps = "repair_steps"
        case testProcedure = "test_procedure"
        case modelsAffected = "models_affected"
        case relatedPatterns = "related_patterns"
    }
}

struct ProbabilityDefinition: Codable, Sendable {
    let cause: String
    let percent: Int
    let description: String
}

struct PatternsFile: Codable, Sendable {
    let version: String
    let patterns: [PatternDefinition]
}

struct ModelDefinition: Codable, Sendable {
    let name: String
    let chip: String
    let year: Int
    let sensors: [String]?
}

struct ModelsFile: Codable, Sendable {
    let models: [String: ModelDefinition]
}

struct ComponentDefinition: Codable, Sendable {
    let name: String
    let aliases: [String]?
    let sensorsOnFlex: [String]?
    let partsIncluded: [String]?
    let difficulty: String
    let estimatedTimeMinutes: Int?
    let ifixitDifficulty: Int?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case name, aliases, difficulty, note
        case sensorsOnFlex = "sensors_on_flex"
        case partsIncluded = "parts_included"
        case estimatedTimeMinutes = "estimated_time_minutes"
        case ifixitDifficulty = "ifixit_difficulty"
    }
}

struct ComponentsFile: Codable, Sendable {
    let components: [String: ComponentDefinition]
}

struct VersionFile: Codable, Sendable {
    let version: String
    let minAppVersion: String
}
