import Foundation

final class KnowledgeBase: Sendable {
    let patterns: [PatternDefinition]
    let models: [String: ModelDefinition]
    let components: [String: ComponentDefinition]
    let version: String

    init() {
        let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("iCrashDiag/knowledge")

        self.patterns = Self.loadPatterns(appSupportDir: appSupportDir)
        self.models = Self.loadModels(appSupportDir: appSupportDir)
        self.components = Self.loadComponents(appSupportDir: appSupportDir)
        self.version = Self.loadVersion(appSupportDir: appSupportDir)
    }

    func modelName(for identifier: String) -> String? {
        models[identifier]?.name
    }

    func findPatterns(in text: String) -> [PatternDefinition] {
        let lowered = text.lowercased()
        return patterns.filter { pattern in
            pattern.keywords.contains { keyword in
                lowered.contains(keyword.lowercased())
            }
        }
    }

    func component(for id: String) -> ComponentDefinition? {
        components[id]
    }

    // MARK: - Private loaders

    private static func loadPatterns(appSupportDir: URL) -> [PatternDefinition] {
        if let data = try? Data(contentsOf: appSupportDir.appendingPathComponent("panic-patterns.json")),
           let file = try? JSONDecoder().decode(PatternsFile.self, from: data) {
            return file.patterns
        }
        guard let url = Bundle.module.url(forResource: "panic-patterns", withExtension: "json", subdirectory: "knowledge"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(PatternsFile.self, from: data) else {
            return []
        }
        return file.patterns
    }

    private static func loadModels(appSupportDir: URL) -> [String: ModelDefinition] {
        if let data = try? Data(contentsOf: appSupportDir.appendingPathComponent("iphone-models.json")),
           let file = try? JSONDecoder().decode(ModelsFile.self, from: data) {
            return file.models
        }
        guard let url = Bundle.module.url(forResource: "iphone-models", withExtension: "json", subdirectory: "knowledge"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(ModelsFile.self, from: data) else {
            return [:]
        }
        return file.models
    }

    private static func loadComponents(appSupportDir: URL) -> [String: ComponentDefinition] {
        if let data = try? Data(contentsOf: appSupportDir.appendingPathComponent("components.json")),
           let file = try? JSONDecoder().decode(ComponentsFile.self, from: data) {
            return file.components
        }
        guard let url = Bundle.module.url(forResource: "components", withExtension: "json", subdirectory: "knowledge"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(ComponentsFile.self, from: data) else {
            return [:]
        }
        return file.components
    }

    private static func loadVersion(appSupportDir: URL) -> String {
        if let data = try? Data(contentsOf: appSupportDir.appendingPathComponent("version.json")),
           let file = try? JSONDecoder().decode(VersionFile.self, from: data) {
            return file.version
        }
        guard let url = Bundle.module.url(forResource: "version", withExtension: "json", subdirectory: "knowledge"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(VersionFile.self, from: data) else {
            return "unknown"
        }
        return file.version
    }
}
