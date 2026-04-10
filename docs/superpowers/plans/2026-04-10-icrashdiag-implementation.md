# iCrashDiag Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS SwiftUI app that parses iPhone `.ips` crash files, diagnoses hardware vs software issues using a JSON knowledge base, and exports structured reports for repair technicians.

**Architecture:** Pure SwiftUI (macOS 14+) with `@Observable` state management. Crash files parsed via protocol-based parser engine. Diagnosis via keyword matching against auto-updating JSON knowledge base. USB extraction via `Process()` calls to libimobiledevice CLI tools.

**Tech Stack:** Swift 6, SwiftUI, Swift Charts, Foundation JSONSerialization, Regex

**Spec:** `docs/superpowers/specs/2026-04-10-icrashdiag-design.md`

**Test data:** `/Users/samuelmuselet/Desktop/iPhone-CrashLogs/` (369 .ips files from iPhone SE 2)

---

## File Map

### Models/ (data structures)
- `iCrashDiag/Models/CrashLog.swift` — CrashLog, CrashCategory, StackFrame, SortOrder
- `iCrashDiag/Models/Diagnosis.swift` — Diagnosis, Severity, Probability
- `iCrashDiag/Models/AnalysisReport.swift` — AnalysisReport, PatternFrequency, Verdict

### Knowledge/ (JSON loading + models)
- `iCrashDiag/Knowledge/KnowledgeModels.swift` — Codable structs for JSON files (PatternDefinition, ComponentDefinition, ModelDefinition)
- `iCrashDiag/Knowledge/KnowledgeBase.swift` — Load bundled + local override JSON, expose lookup methods
- `iCrashDiag/Knowledge/KnowledgeBaseManager.swift` — Check GitHub for updates, download to app support dir

### Parsing/ (crash file parsers)
- `iCrashDiag/Parsing/CrashParserEngine.swift` — CrashParser protocol, engine coordinator, directory parsing with TaskGroup
- `iCrashDiag/Parsing/KernelPanicParser.swift` — bug_type 210
- `iCrashDiag/Parsing/WatchdogParser.swift` — bug_type 409
- `iCrashDiag/Parsing/JetsamParser.swift` — bug_type 298
- `iCrashDiag/Parsing/AppCrashParser.swift` — bug_type 308, 309
- `iCrashDiag/Parsing/GPUEventParser.swift` — bug_type 284
- `iCrashDiag/Parsing/OTAUpdateParser.swift` — bug_type 183
- `iCrashDiag/Parsing/ThermalEventParser.swift` — bug_type 313

### Diagnosis/
- `iCrashDiag/Diagnosis/DiagnosisEngine.swift` — Pattern matching, confidence scoring, aggregate analysis

### Services/
- `iCrashDiag/Services/USBDeviceService.swift` — libimobiledevice Process calls
- `iCrashDiag/Services/ExportService.swift` — Markdown + JSON export

### ViewModels/
- `iCrashDiag/ViewModels/AppViewModel.swift` — @Observable central state

### Views/
- `iCrashDiag/iCrashDiagApp.swift` — @main entry point
- `iCrashDiag/ContentView.swift` — NavigationSplitView 3-column shell
- `iCrashDiag/Views/Sidebar/SidebarView.swift` — Import buttons, category/severity filters, stats
- `iCrashDiag/Views/CrashList/CrashListView.swift` — Searchable sorted list
- `iCrashDiag/Views/CrashList/CrashRowView.swift` — Individual row with severity color + badge
- `iCrashDiag/Views/Detail/CrashDetailView.swift` — Full diagnosis panel
- `iCrashDiag/Views/Detail/DiagnosisCardView.swift` — Severity badge, confidence, component
- `iCrashDiag/Views/Detail/ProbabilityBarsView.swift` — Horizontal bar chart
- `iCrashDiag/Views/Detail/RawPanicView.swift` — Collapsible raw text with keyword highlights
- `iCrashDiag/Views/Overview/OverviewView.swift` — Aggregate report with verdict
- `iCrashDiag/Views/Overview/TimelineChartView.swift` — SwiftUI Charts crashes/day
- `iCrashDiag/Views/Shared/SeverityBadge.swift` — Color-coded severity pill
- `iCrashDiag/Views/Shared/CategoryBadge.swift` — Category label pill

### Resources/
- `iCrashDiag/Resources/knowledge/iphone-models.json`
- `iCrashDiag/Resources/knowledge/panic-patterns.json`
- `iCrashDiag/Resources/knowledge/components.json`
- `iCrashDiag/Resources/knowledge/version.json`

### Root knowledge/ (git-tracked source for auto-update)
- `knowledge/iphone-models.json`
- `knowledge/panic-patterns.json`
- `knowledge/components.json`
- `knowledge/version.json`

---

## Task 1: Xcode Project Scaffold

**Files:**
- Create: `iCrashDiag/iCrashDiagApp.swift`
- Create: `iCrashDiag/ContentView.swift`

- [ ] **Step 1: Create Xcode project via command line**

```bash
cd /Users/samuelmuselet/Desktop/iCrashDiag
mkdir -p iCrashDiag/Models iCrashDiag/Parsing iCrashDiag/Diagnosis iCrashDiag/Knowledge iCrashDiag/Services iCrashDiag/ViewModels iCrashDiag/Views/Sidebar iCrashDiag/Views/CrashList iCrashDiag/Views/Detail iCrashDiag/Views/Overview iCrashDiag/Views/Shared iCrashDiag/Resources/knowledge
```

- [ ] **Step 2: Create Package.swift for SwiftPM-based project**

Use a SwiftPM executable instead of .xcodeproj (simpler for open-source, no Xcode project file to maintain):

```swift
// Package.swift
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "iCrashDiag",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "iCrashDiag",
            path: "iCrashDiag",
            resources: [
                .copy("Resources/knowledge")
            ]
        )
    ]
)
```

- [ ] **Step 3: Create app entry point**

```swift
// iCrashDiag/iCrashDiagApp.swift
import SwiftUI

@main
struct iCrashDiagApp: App {
    @State private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(viewModel)
        }
        .defaultSize(width: 1200, height: 750)
    }
}
```

- [ ] **Step 4: Create placeholder ContentView**

```swift
// iCrashDiag/ContentView.swift
import SwiftUI

struct ContentView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        NavigationSplitView {
            Text("Sidebar")
        } content: {
            Text("Crash List")
        } detail: {
            Text("Detail")
        }
        .navigationSplitViewStyle(.balanced)
    }
}
```

- [ ] **Step 5: Create minimal AppViewModel stub**

```swift
// iCrashDiag/ViewModels/AppViewModel.swift
import SwiftUI

@Observable
final class AppViewModel {
    var crashLogs: [CrashLog] = []
    var selectedCrashID: UUID?
    var isLoading = false
    var loadingProgress: Double = 0
    var loadingMessage = ""
}
```

- [ ] **Step 6: Create CrashLog stub for compilation**

```swift
// iCrashDiag/Models/CrashLog.swift
import Foundation

enum CrashCategory: String, Codable, CaseIterable {
    case kernelPanic = "Kernel Panic"
    case thermal = "Thermal Event"
    case jetsam = "Jetsam (Memory)"
    case appCrash = "App Crash"
    case gpuEvent = "GPU Event"
    case otaUpdate = "OTA Update"
    case watchdog = "Watchdog Timeout"
    case diskResource = "Disk Resource"
    case unknown = "Unknown"
}

enum Severity: String, Codable, CaseIterable {
    case critical
    case hardware
    case software
    case informational
}

struct CrashLog: Identifiable, Codable {
    let id: UUID
    let fileName: String
    let bugType: Int
    let category: CrashCategory
    let timestamp: Date
    let osVersion: String
    let deviceModel: String
    let deviceName: String?
    var diagnosis: Diagnosis?

    let rawMetadata: String
    let rawBody: String
}
```

- [ ] **Step 7: Create Diagnosis stub**

```swift
// iCrashDiag/Models/Diagnosis.swift
import Foundation

struct Diagnosis: Codable {
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

struct Probability: Codable {
    let cause: String
    let percent: Int
    let description: String
}
```

- [ ] **Step 8: Build and verify**

```bash
cd /Users/samuelmuselet/Desktop/iCrashDiag
swift build 2>&1
```

Expected: BUILD SUCCEEDED. The app skeleton compiles with 3-column NavigationSplitView.

- [ ] **Step 9: Commit**

```bash
git add Package.swift iCrashDiag/
git commit -m "feat: project scaffold — SwiftPM, app entry, 3-column layout, model stubs"
```

---

## Task 2: Knowledge Base JSON Files + Loader

**Files:**
- Create: `knowledge/iphone-models.json`
- Create: `knowledge/panic-patterns.json`
- Create: `knowledge/components.json`
- Create: `knowledge/version.json`
- Copy to: `iCrashDiag/Resources/knowledge/` (same files)
- Create: `iCrashDiag/Knowledge/KnowledgeModels.swift`
- Create: `iCrashDiag/Knowledge/KnowledgeBase.swift`

- [ ] **Step 1: Create iphone-models.json**

```json
{
  "models": {
    "iPhone1,1": { "name": "iPhone 2G", "chip": "APL0098", "year": 2007 },
    "iPhone1,2": { "name": "iPhone 3G", "chip": "APL0098", "year": 2008 },
    "iPhone2,1": { "name": "iPhone 3GS", "chip": "APL0298", "year": 2009 },
    "iPhone3,1": { "name": "iPhone 4", "chip": "A4", "year": 2010 },
    "iPhone3,2": { "name": "iPhone 4", "chip": "A4", "year": 2010 },
    "iPhone3,3": { "name": "iPhone 4", "chip": "A4", "year": 2010 },
    "iPhone4,1": { "name": "iPhone 4S", "chip": "A5", "year": 2011 },
    "iPhone5,1": { "name": "iPhone 5", "chip": "A6", "year": 2012 },
    "iPhone5,2": { "name": "iPhone 5", "chip": "A6", "year": 2012 },
    "iPhone5,3": { "name": "iPhone 5c", "chip": "A6", "year": 2013 },
    "iPhone5,4": { "name": "iPhone 5c", "chip": "A6", "year": 2013 },
    "iPhone6,1": { "name": "iPhone 5s", "chip": "A7", "year": 2013 },
    "iPhone6,2": { "name": "iPhone 5s", "chip": "A7", "year": 2013 },
    "iPhone7,1": { "name": "iPhone 6 Plus", "chip": "A8", "year": 2014 },
    "iPhone7,2": { "name": "iPhone 6", "chip": "A8", "year": 2014 },
    "iPhone8,1": { "name": "iPhone 6s", "chip": "A9", "year": 2015, "sensors": ["mic1", "mic2", "als", "prox"] },
    "iPhone8,2": { "name": "iPhone 6s Plus", "chip": "A9", "year": 2015, "sensors": ["mic1", "mic2", "als", "prox"] },
    "iPhone8,4": { "name": "iPhone SE", "chip": "A9", "year": 2016, "sensors": ["mic1", "mic2", "als", "prox"] },
    "iPhone9,1": { "name": "iPhone 7", "chip": "A10 Fusion", "year": 2016, "sensors": ["mic1", "mic2", "als", "prox"] },
    "iPhone9,2": { "name": "iPhone 7 Plus", "chip": "A10 Fusion", "year": 2016, "sensors": ["mic1", "mic2", "als", "prox"] },
    "iPhone9,3": { "name": "iPhone 7", "chip": "A10 Fusion", "year": 2016, "sensors": ["mic1", "mic2", "als", "prox"] },
    "iPhone9,4": { "name": "iPhone 7 Plus", "chip": "A10 Fusion", "year": 2016, "sensors": ["mic1", "mic2", "als", "prox"] },
    "iPhone10,1": { "name": "iPhone 8", "chip": "A11 Bionic", "year": 2017, "sensors": ["mic1", "mic2", "als", "prox"] },
    "iPhone10,2": { "name": "iPhone 8 Plus", "chip": "A11 Bionic", "year": 2017, "sensors": ["mic1", "mic2", "als", "prox"] },
    "iPhone10,3": { "name": "iPhone X", "chip": "A11 Bionic", "year": 2017, "sensors": ["mic1", "mic2", "mic3", "als", "prox", "flood", "dot"] },
    "iPhone10,4": { "name": "iPhone 8", "chip": "A11 Bionic", "year": 2017, "sensors": ["mic1", "mic2", "als", "prox"] },
    "iPhone10,5": { "name": "iPhone 8 Plus", "chip": "A11 Bionic", "year": 2017, "sensors": ["mic1", "mic2", "als", "prox"] },
    "iPhone10,6": { "name": "iPhone X", "chip": "A11 Bionic", "year": 2017, "sensors": ["mic1", "mic2", "mic3", "als", "prox", "flood", "dot"] },
    "iPhone11,2": { "name": "iPhone XS", "chip": "A12 Bionic", "year": 2018, "sensors": ["mic1", "mic2", "mic3", "als", "prox", "flood", "dot"] },
    "iPhone11,4": { "name": "iPhone XS Max", "chip": "A12 Bionic", "year": 2018, "sensors": ["mic1", "mic2", "mic3", "als", "prox", "flood", "dot"] },
    "iPhone11,6": { "name": "iPhone XS Max", "chip": "A12 Bionic", "year": 2018, "sensors": ["mic1", "mic2", "mic3", "als", "prox", "flood", "dot"] },
    "iPhone11,8": { "name": "iPhone XR", "chip": "A12 Bionic", "year": 2018, "sensors": ["mic1", "mic2", "als", "prox"] },
    "iPhone12,1": { "name": "iPhone 11", "chip": "A13 Bionic", "year": 2019, "sensors": ["mic1", "mic2", "als", "prox"] },
    "iPhone12,3": { "name": "iPhone 11 Pro", "chip": "A13 Bionic", "year": 2019, "sensors": ["mic1", "mic2", "mic3", "als", "prox"] },
    "iPhone12,5": { "name": "iPhone 11 Pro Max", "chip": "A13 Bionic", "year": 2019, "sensors": ["mic1", "mic2", "mic3", "als", "prox"] },
    "iPhone12,8": { "name": "iPhone SE (2nd gen)", "chip": "A13 Bionic", "year": 2020, "sensors": ["mic1", "mic2", "als", "prox"] },
    "iPhone13,1": { "name": "iPhone 12 mini", "chip": "A14 Bionic", "year": 2020, "sensors": ["mic1", "mic2", "mic3", "als", "prox", "lidar"] },
    "iPhone13,2": { "name": "iPhone 12", "chip": "A14 Bionic", "year": 2020, "sensors": ["mic1", "mic2", "mic3", "als", "prox"] },
    "iPhone13,3": { "name": "iPhone 12 Pro", "chip": "A14 Bionic", "year": 2020, "sensors": ["mic1", "mic2", "mic3", "als", "prox", "lidar"] },
    "iPhone13,4": { "name": "iPhone 12 Pro Max", "chip": "A14 Bionic", "year": 2020, "sensors": ["mic1", "mic2", "mic3", "als", "prox", "lidar"] },
    "iPhone14,2": { "name": "iPhone 13 Pro", "chip": "A15 Bionic", "year": 2021, "sensors": ["mic1", "mic2", "mic3", "als", "prox", "lidar"] },
    "iPhone14,3": { "name": "iPhone 13 Pro Max", "chip": "A15 Bionic", "year": 2021, "sensors": ["mic1", "mic2", "mic3", "als", "prox", "lidar"] },
    "iPhone14,4": { "name": "iPhone 13 mini", "chip": "A15 Bionic", "year": 2021, "sensors": ["mic1", "mic2", "mic3", "als", "prox"] },
    "iPhone14,5": { "name": "iPhone 13", "chip": "A15 Bionic", "year": 2021, "sensors": ["mic1", "mic2", "mic3", "als", "prox"] },
    "iPhone14,6": { "name": "iPhone SE (3rd gen)", "chip": "A15 Bionic", "year": 2022, "sensors": ["mic1", "mic2", "als", "prox"] },
    "iPhone14,7": { "name": "iPhone 14", "chip": "A15 Bionic", "year": 2022, "sensors": ["mic1", "mic2", "mic3", "als", "prox"] },
    "iPhone14,8": { "name": "iPhone 14 Plus", "chip": "A15 Bionic", "year": 2022, "sensors": ["mic1", "mic2", "mic3", "als", "prox"] },
    "iPhone15,2": { "name": "iPhone 14 Pro", "chip": "A16 Bionic", "year": 2022, "sensors": ["mic1", "mic2", "mic3", "als", "prox", "lidar"] },
    "iPhone15,3": { "name": "iPhone 14 Pro Max", "chip": "A16 Bionic", "year": 2022, "sensors": ["mic1", "mic2", "mic3", "als", "prox", "lidar"] },
    "iPhone15,4": { "name": "iPhone 15", "chip": "A16 Bionic", "year": 2023, "sensors": ["mic1", "mic2", "mic3", "als", "prox"] },
    "iPhone15,5": { "name": "iPhone 15 Plus", "chip": "A16 Bionic", "year": 2023, "sensors": ["mic1", "mic2", "mic3", "als", "prox"] },
    "iPhone16,1": { "name": "iPhone 15 Pro", "chip": "A17 Pro", "year": 2023, "sensors": ["mic1", "mic2", "mic3", "als", "prox", "lidar"] },
    "iPhone16,2": { "name": "iPhone 15 Pro Max", "chip": "A17 Pro", "year": 2023, "sensors": ["mic1", "mic2", "mic3", "als", "prox", "lidar"] },
    "iPhone17,1": { "name": "iPhone 16 Pro", "chip": "A18 Pro", "year": 2024, "sensors": ["mic1", "mic2", "mic3", "als", "prox", "lidar"] },
    "iPhone17,2": { "name": "iPhone 16 Pro Max", "chip": "A18 Pro", "year": 2024, "sensors": ["mic1", "mic2", "mic3", "als", "prox", "lidar"] },
    "iPhone17,3": { "name": "iPhone 16", "chip": "A18", "year": 2024, "sensors": ["mic1", "mic2", "mic3", "als", "prox"] },
    "iPhone17,4": { "name": "iPhone 16 Plus", "chip": "A18", "year": 2024, "sensors": ["mic1", "mic2", "mic3", "als", "prox"] },
    "iPhone17,5": { "name": "iPhone 16e", "chip": "A16 Bionic", "year": 2025, "sensors": ["mic1", "mic2", "als", "prox"] }
  }
}
```

Write this file to both `knowledge/iphone-models.json` AND `iCrashDiag/Resources/knowledge/iphone-models.json` (identical content).

- [ ] **Step 2: Create panic-patterns.json**

Use the full content from the spec (section "panic-patterns.json") — all 8 patterns (mic1_missing, thermalmonitord_watchdog, gpu_hang, kernel_data_abort, watchdog_backboardd, watchdog_wifid, sep_panic, jetsam_memory_pressure).

Write to both `knowledge/panic-patterns.json` AND `iCrashDiag/Resources/knowledge/panic-patterns.json`.

- [ ] **Step 3: Create components.json**

Use the full content from the spec (section "components.json") — all 8 components.

Write to both `knowledge/components.json` AND `iCrashDiag/Resources/knowledge/components.json`.

- [ ] **Step 4: Create version.json**

```json
{
  "version": "2026.04.10",
  "minAppVersion": "1.0"
}
```

Write to both `knowledge/version.json` AND `iCrashDiag/Resources/knowledge/version.json`.

- [ ] **Step 5: Create KnowledgeModels.swift**

```swift
// iCrashDiag/Knowledge/KnowledgeModels.swift
import Foundation

struct PatternDefinition: Codable {
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

struct ProbabilityDefinition: Codable {
    let cause: String
    let percent: Int
    let description: String
}

struct PatternsFile: Codable {
    let version: String
    let patterns: [PatternDefinition]
}

struct ModelDefinition: Codable {
    let name: String
    let chip: String
    let year: Int
    let sensors: [String]?
}

struct ModelsFile: Codable {
    let models: [String: ModelDefinition]
}

struct ComponentDefinition: Codable {
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

struct ComponentsFile: Codable {
    let components: [String: ComponentDefinition]
}

struct VersionFile: Codable {
    let version: String
    let minAppVersion: String
}
```

- [ ] **Step 6: Create KnowledgeBase.swift**

```swift
// iCrashDiag/Knowledge/KnowledgeBase.swift
import Foundation

final class KnowledgeBase: Sendable {
    let patterns: [PatternDefinition]
    let models: [String: ModelDefinition]
    let components: [String: ComponentDefinition]
    let version: String

    init() {
        let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("iCrashDiag/knowledge")

        // Load with priority: appSupport override > bundled
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
        guard let url = Bundle.main.url(forResource: "panic-patterns", withExtension: "json", subdirectory: "knowledge"),
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
        guard let url = Bundle.main.url(forResource: "iphone-models", withExtension: "json", subdirectory: "knowledge"),
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
        guard let url = Bundle.main.url(forResource: "components", withExtension: "json", subdirectory: "knowledge"),
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
        guard let url = Bundle.main.url(forResource: "version", withExtension: "json", subdirectory: "knowledge"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(VersionFile.self, from: data) else {
            return "unknown"
        }
        return file.version
    }
}
```

- [ ] **Step 7: Build and verify**

```bash
cd /Users/samuelmuselet/Desktop/iCrashDiag && swift build 2>&1
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 8: Commit**

```bash
git add knowledge/ iCrashDiag/Resources/knowledge/ iCrashDiag/Knowledge/
git commit -m "feat: knowledge base — JSON files + loader with app support override"
```

---

## Task 3: Complete Data Models

**Files:**
- Modify: `iCrashDiag/Models/CrashLog.swift`
- Modify: `iCrashDiag/Models/Diagnosis.swift`
- Create: `iCrashDiag/Models/AnalysisReport.swift`

- [ ] **Step 1: Expand CrashLog with all fields**

```swift
// iCrashDiag/Models/CrashLog.swift
import Foundation

enum CrashCategory: String, Codable, CaseIterable, Identifiable {
    case kernelPanic = "Kernel Panic"
    case thermal = "Thermal Event"
    case jetsam = "Jetsam (Memory)"
    case appCrash = "App Crash"
    case gpuEvent = "GPU Event"
    case otaUpdate = "OTA Update"
    case watchdog = "Watchdog Timeout"
    case diskResource = "Disk Resource"
    case unknown = "Unknown"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .kernelPanic: "exclamationmark.triangle.fill"
        case .thermal: "thermometer.sun.fill"
        case .jetsam: "memorychip.fill"
        case .appCrash: "app.badge.fill"
        case .gpuEvent: "gpu"
        case .otaUpdate: "arrow.down.circle.fill"
        case .watchdog: "clock.badge.exclamationmark.fill"
        case .diskResource: "externaldrive.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }

    static func from(bugType: Int) -> CrashCategory {
        switch bugType {
        case 210: .kernelPanic
        case 298: .jetsam
        case 308, 309: .appCrash
        case 284: .gpuEvent
        case 183: .otaUpdate
        case 313: .thermal
        case 409: .watchdog
        default: .unknown
        }
    }
}

enum Severity: String, Codable, CaseIterable, Identifiable {
    case critical
    case hardware
    case software
    case informational

    var id: String { rawValue }

    var label: String {
        switch self {
        case .critical: "Critical"
        case .hardware: "Hardware"
        case .software: "Software"
        case .informational: "Info"
        }
    }

    var color: String {
        switch self {
        case .critical: "red"
        case .hardware: "orange"
        case .software: "yellow"
        case .informational: "gray"
        }
    }
}

enum SortOrder: String, CaseIterable {
    case dateDescending = "Newest First"
    case dateAscending = "Oldest First"
    case severity = "Severity"
    case category = "Category"
}

struct StackFrame: Codable {
    let index: Int
    let image: String?
    let address: String?
    let symbol: String?
}

struct CrashLog: Identifiable, Codable, Hashable {
    let id: UUID
    let fileName: String
    let bugType: Int
    let category: CrashCategory
    let timestamp: Date
    let osVersion: String
    let buildVersion: String?
    let deviceModel: String
    let deviceName: String?

    // Panic-specific
    let panicString: String?
    let missingSensors: [String]
    let faultingService: String?
    let cpuCaller: String?

    // App crash-specific
    let processName: String?
    let bundleID: String?
    let exceptionType: String?
    let terminationReason: String?
    let faultingThread: Int?

    // GPU-specific
    let gpuRestartReason: String?
    let gpuSignature: Int?

    // Jetsam-specific
    let largestProcess: String?
    let freePages: Int?
    let activePages: Int?

    // OTA-specific
    let restoreError: Int?

    // Raw
    let rawMetadata: String
    let rawBody: String

    // Diagnosis (set after analysis)
    var diagnosis: Diagnosis?

    static func == (lhs: CrashLog, rhs: CrashLog) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
```

- [ ] **Step 2: Create AnalysisReport.swift**

```swift
// iCrashDiag/Models/AnalysisReport.swift
import Foundation

struct PatternFrequency: Codable, Identifiable {
    var id: String { patternID }
    let patternID: String
    let title: String
    let count: Int
    let severity: Severity
    let component: String
}

struct Verdict: Codable {
    let isHardware: Bool
    let confidence: Int
    let summary: String
}

struct AnalysisReport: Codable {
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

struct DateRange: Codable {
    let start: Date
    let end: Date
}
```

- [ ] **Step 3: Build and verify**

```bash
cd /Users/samuelmuselet/Desktop/iCrashDiag && swift build 2>&1
```

- [ ] **Step 4: Commit**

```bash
git add iCrashDiag/Models/
git commit -m "feat: complete data models — CrashLog, Diagnosis, AnalysisReport"
```

---

## Task 4: Parsing Engine + All Parsers

**Files:**
- Create: `iCrashDiag/Parsing/CrashParserEngine.swift`
- Create: `iCrashDiag/Parsing/KernelPanicParser.swift`
- Create: `iCrashDiag/Parsing/WatchdogParser.swift`
- Create: `iCrashDiag/Parsing/JetsamParser.swift`
- Create: `iCrashDiag/Parsing/AppCrashParser.swift`
- Create: `iCrashDiag/Parsing/GPUEventParser.swift`
- Create: `iCrashDiag/Parsing/OTAUpdateParser.swift`
- Create: `iCrashDiag/Parsing/ThermalEventParser.swift`

This is the core parsing logic. Every .ips file has JSON metadata on line 1, then a body that varies by bug_type. Some bodies are JSON (panic, jetsam, app crash, GPU, thermal), some are plain text (OTA).

- [ ] **Step 1: Create CrashParserEngine.swift**

```swift
// iCrashDiag/Parsing/CrashParserEngine.swift
import Foundation

protocol CrashParser: Sendable {
    func canParse(bugType: Int) -> Bool
    func parse(fileName: String, bugType: Int, metadata: [String: Any], metadataRaw: String, body: String, knowledgeBase: KnowledgeBase) -> CrashLog?
}

final class CrashParserEngine: Sendable {
    let parsers: [CrashParser]
    let knowledgeBase: KnowledgeBase

    init(knowledgeBase: KnowledgeBase) {
        self.knowledgeBase = knowledgeBase
        self.parsers = [
            KernelPanicParser(),
            WatchdogParser(),
            JetsamParser(),
            AppCrashParser(),
            GPUEventParser(),
            OTAUpdateParser(),
            ThermalEventParser(),
        ]
    }

    func parseFile(url: URL) throws -> CrashLog? {
        let content = try String(contentsOf: url, encoding: .utf8)
        guard let firstNewline = content.firstIndex(of: "\n") else { return nil }

        let metadataRaw = String(content[content.startIndex..<firstNewline])
        let body = String(content[content.index(after: firstNewline)...])

        guard let metadataData = metadataRaw.data(using: .utf8),
              let metadataObj = try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any] else {
            return nil
        }

        let bugTypeStr = metadataObj["bug_type"] as? String ?? ""
        let bugType = Int(bugTypeStr) ?? 0

        for parser in parsers {
            if parser.canParse(bugType: bugType) {
                return parser.parse(
                    fileName: url.lastPathComponent,
                    bugType: bugType,
                    metadata: metadataObj,
                    metadataRaw: metadataRaw,
                    body: body,
                    knowledgeBase: knowledgeBase
                )
            }
        }

        // Fallback: unknown type
        let timestamp = Self.parseTimestamp(metadataObj["timestamp"] as? String)
        return CrashLog(
            id: UUID(), fileName: url.lastPathComponent, bugType: bugType,
            category: .unknown, timestamp: timestamp ?? Date(),
            osVersion: metadataObj["os_version"] as? String ?? "Unknown",
            buildVersion: nil, deviceModel: "Unknown", deviceName: nil,
            panicString: nil, missingSensors: [], faultingService: nil, cpuCaller: nil,
            processName: nil, bundleID: nil, exceptionType: nil, terminationReason: nil, faultingThread: nil,
            gpuRestartReason: nil, gpuSignature: nil,
            largestProcess: nil, freePages: nil, activePages: nil,
            restoreError: nil,
            rawMetadata: metadataRaw, rawBody: body, diagnosis: nil
        )
    }

    func parseDirectory(url: URL, progress: @Sendable @escaping (Double, String) -> Void) async -> [CrashLog] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: nil) else { return [] }

        var ipsFiles: [URL] = []
        while let fileURL = enumerator.nextObject() as? URL {
            if fileURL.pathExtension.lowercased() == "ips" {
                ipsFiles.append(fileURL)
            }
        }

        let total = ipsFiles.count
        guard total > 0 else { return [] }

        var results: [CrashLog] = []
        for (index, fileURL) in ipsFiles.enumerated() {
            if let crash = try? self.parseFile(url: fileURL) {
                results.append(crash)
            }
            let pct = Double(index + 1) / Double(total)
            progress(pct, "Parsing \(index + 1)/\(total): \(fileURL.lastPathComponent)")
        }
        return results.sorted { $0.timestamp > $1.timestamp }
    }

    static func parseTimestamp(_ str: String?) -> Date? {
        guard let str else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SS Z"
        if let d = formatter.date(from: str) { return d }
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.date(from: str)
    }

    static func extractMissingSensors(from text: String) -> [String] {
        let pattern = /Missing sensor\(?s?\)?: (.+?)[\n\\]/
        guard let match = text.firstMatch(of: pattern) else { return [] }
        return String(match.1).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func extractFaultingService(from text: String) -> String? {
        let pattern = /no successful checkins from (\S+)/
        return text.firstMatch(of: pattern).map { String($0.1) }
    }

    static func extractCPUCaller(from text: String) -> String? {
        let pattern = /cpu (\d+) caller (0x[\da-fA-F]+)/
        guard let match = text.firstMatch(of: pattern) else { return nil }
        return "cpu \(match.1) caller \(match.2)"
    }
}
```

- [ ] **Step 2: Create KernelPanicParser.swift**

```swift
// iCrashDiag/Parsing/KernelPanicParser.swift
import Foundation

struct KernelPanicParser: CrashParser {
    func canParse(bugType: Int) -> Bool { bugType == 210 }

    func parse(fileName: String, bugType: Int, metadata: [String: Any], metadataRaw: String, body: String, knowledgeBase: KnowledgeBase) -> CrashLog? {
        guard let bodyData = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            return nil
        }

        let product = json["product"] as? String ?? "Unknown"
        let panicString = json["panicString"] as? String ?? body
        let timestamp = CrashParserEngine.parseTimestamp(metadata["timestamp"] as? String)

        return CrashLog(
            id: UUID(), fileName: fileName, bugType: bugType,
            category: .kernelPanic, timestamp: timestamp ?? Date(),
            osVersion: metadata["os_version"] as? String ?? "Unknown",
            buildVersion: json["build"] as? String,
            deviceModel: product, deviceName: knowledgeBase.modelName(for: product),
            panicString: panicString,
            missingSensors: CrashParserEngine.extractMissingSensors(from: panicString),
            faultingService: CrashParserEngine.extractFaultingService(from: panicString),
            cpuCaller: CrashParserEngine.extractCPUCaller(from: panicString),
            processName: nil, bundleID: nil, exceptionType: nil, terminationReason: nil, faultingThread: nil,
            gpuRestartReason: nil, gpuSignature: nil,
            largestProcess: nil, freePages: nil, activePages: nil,
            restoreError: nil,
            rawMetadata: metadataRaw, rawBody: body, diagnosis: nil
        )
    }
}
```

- [ ] **Step 3: Create WatchdogParser.swift**

```swift
// iCrashDiag/Parsing/WatchdogParser.swift
import Foundation

struct WatchdogParser: CrashParser {
    func canParse(bugType: Int) -> Bool { bugType == 409 }

    func parse(fileName: String, bugType: Int, metadata: [String: Any], metadataRaw: String, body: String, knowledgeBase: KnowledgeBase) -> CrashLog? {
        let json = (try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any]) ?? [:]

        let product = json["product"] as? String ?? "Unknown"
        let panicString = json["panicString"] as? String ?? body
        let timestamp = CrashParserEngine.parseTimestamp(metadata["timestamp"] as? String)

        return CrashLog(
            id: UUID(), fileName: fileName, bugType: bugType,
            category: .watchdog, timestamp: timestamp ?? Date(),
            osVersion: metadata["os_version"] as? String ?? "Unknown",
            buildVersion: json["build"] as? String,
            deviceModel: product, deviceName: knowledgeBase.modelName(for: product),
            panicString: panicString,
            missingSensors: CrashParserEngine.extractMissingSensors(from: panicString),
            faultingService: CrashParserEngine.extractFaultingService(from: panicString),
            cpuCaller: CrashParserEngine.extractCPUCaller(from: panicString),
            processName: nil, bundleID: nil, exceptionType: nil, terminationReason: nil, faultingThread: nil,
            gpuRestartReason: nil, gpuSignature: nil,
            largestProcess: nil, freePages: nil, activePages: nil,
            restoreError: nil,
            rawMetadata: metadataRaw, rawBody: body, diagnosis: nil
        )
    }
}
```

- [ ] **Step 4: Create JetsamParser.swift**

```swift
// iCrashDiag/Parsing/JetsamParser.swift
import Foundation

struct JetsamParser: CrashParser {
    func canParse(bugType: Int) -> Bool { bugType == 298 }

    func parse(fileName: String, bugType: Int, metadata: [String: Any], metadataRaw: String, body: String, knowledgeBase: KnowledgeBase) -> CrashLog? {
        let json = (try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any]) ?? [:]

        let timestamp = CrashParserEngine.parseTimestamp(metadata["timestamp"] as? String)
        let memPages = json["memoryPages"] as? [String: Any]
        let largestProc = json["largestProcess"] as? String

        return CrashLog(
            id: UUID(), fileName: fileName, bugType: bugType,
            category: .jetsam, timestamp: timestamp ?? Date(),
            osVersion: metadata["os_version"] as? String ?? "Unknown",
            buildVersion: nil, deviceModel: "Unknown", deviceName: nil,
            panicString: nil, missingSensors: [], faultingService: nil, cpuCaller: nil,
            processName: nil, bundleID: nil, exceptionType: nil, terminationReason: nil, faultingThread: nil,
            gpuRestartReason: nil, gpuSignature: nil,
            largestProcess: largestProc,
            freePages: memPages?["free"] as? Int,
            activePages: memPages?["active"] as? Int,
            restoreError: nil,
            rawMetadata: metadataRaw, rawBody: body, diagnosis: nil
        )
    }
}
```

- [ ] **Step 5: Create AppCrashParser.swift**

```swift
// iCrashDiag/Parsing/AppCrashParser.swift
import Foundation

struct AppCrashParser: CrashParser {
    func canParse(bugType: Int) -> Bool { bugType == 308 || bugType == 309 }

    func parse(fileName: String, bugType: Int, metadata: [String: Any], metadataRaw: String, body: String, knowledgeBase: KnowledgeBase) -> CrashLog? {
        let json = (try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any]) ?? [:]

        let timestamp = CrashParserEngine.parseTimestamp(metadata["timestamp"] as? String)
        let exception = json["exception"] as? [String: Any]
        let termination = json["termination"] as? [String: Any]

        return CrashLog(
            id: UUID(), fileName: fileName, bugType: bugType,
            category: .appCrash, timestamp: timestamp ?? Date(),
            osVersion: metadata["os_version"] as? String ?? "Unknown",
            buildVersion: nil, deviceModel: "Unknown", deviceName: nil,
            panicString: nil, missingSensors: [], faultingService: nil, cpuCaller: nil,
            processName: metadata["app_name"] as? String ?? json["procName"] as? String,
            bundleID: metadata["bundleID"] as? String,
            exceptionType: exception?["type"] as? String,
            terminationReason: termination?["indicator"] as? String,
            faultingThread: json["faultingThread"] as? Int,
            gpuRestartReason: nil, gpuSignature: nil,
            largestProcess: nil, freePages: nil, activePages: nil,
            restoreError: nil,
            rawMetadata: metadataRaw, rawBody: body, diagnosis: nil
        )
    }
}
```

- [ ] **Step 6: Create GPUEventParser.swift**

```swift
// iCrashDiag/Parsing/GPUEventParser.swift
import Foundation

struct GPUEventParser: CrashParser {
    func canParse(bugType: Int) -> Bool { bugType == 284 }

    func parse(fileName: String, bugType: Int, metadata: [String: Any], metadataRaw: String, body: String, knowledgeBase: KnowledgeBase) -> CrashLog? {
        let json = (try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any]) ?? [:]

        let timestamp = CrashParserEngine.parseTimestamp(metadata["timestamp"] as? String)
        let analysis = json["analysis"] as? [String: Any]

        return CrashLog(
            id: UUID(), fileName: fileName, bugType: bugType,
            category: .gpuEvent, timestamp: timestamp ?? Date(),
            osVersion: metadata["os_version"] as? String ?? "Unknown",
            buildVersion: nil, deviceModel: "Unknown", deviceName: nil,
            panicString: nil, missingSensors: [], faultingService: nil, cpuCaller: nil,
            processName: metadata["process_name"] as? String ?? json["process_name"] as? String,
            bundleID: nil, exceptionType: nil, terminationReason: nil, faultingThread: nil,
            gpuRestartReason: analysis?["restart_reason_desc"] as? String,
            gpuSignature: analysis?["signature"] as? Int,
            largestProcess: nil, freePages: nil, activePages: nil,
            restoreError: nil,
            rawMetadata: metadataRaw, rawBody: body, diagnosis: nil
        )
    }
}
```

- [ ] **Step 7: Create OTAUpdateParser.swift**

```swift
// iCrashDiag/Parsing/OTAUpdateParser.swift
import Foundation

struct OTAUpdateParser: CrashParser {
    func canParse(bugType: Int) -> Bool { bugType == 183 }

    func parse(fileName: String, bugType: Int, metadata: [String: Any], metadataRaw: String, body: String, knowledgeBase: KnowledgeBase) -> CrashLog? {
        // OTA body is plain text, not JSON
        let timestamp = CrashParserEngine.parseTimestamp(metadata["timestamp"] as? String)
        let restoreError = (metadata["restore_error"] as? String).flatMap(Int.init)

        return CrashLog(
            id: UUID(), fileName: fileName, bugType: bugType,
            category: .otaUpdate, timestamp: timestamp ?? Date(),
            osVersion: metadata["os_version"] as? String ?? metadata["itunes_version"] as? String ?? "Unknown",
            buildVersion: nil, deviceModel: "Unknown", deviceName: nil,
            panicString: nil, missingSensors: [], faultingService: nil, cpuCaller: nil,
            processName: nil, bundleID: nil, exceptionType: nil, terminationReason: nil, faultingThread: nil,
            gpuRestartReason: nil, gpuSignature: nil,
            largestProcess: nil, freePages: nil, activePages: nil,
            restoreError: restoreError,
            rawMetadata: metadataRaw, rawBody: body, diagnosis: nil
        )
    }
}
```

- [ ] **Step 8: Create ThermalEventParser.swift**

```swift
// iCrashDiag/Parsing/ThermalEventParser.swift
import Foundation

struct ThermalEventParser: CrashParser {
    func canParse(bugType: Int) -> Bool { bugType == 313 }

    func parse(fileName: String, bugType: Int, metadata: [String: Any], metadataRaw: String, body: String, knowledgeBase: KnowledgeBase) -> CrashLog? {
        let json = (try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any]) ?? [:]
        let timestamp = CrashParserEngine.parseTimestamp(metadata["timestamp"] as? String)
        let product = json["product"] as? String ?? "Unknown"

        return CrashLog(
            id: UUID(), fileName: fileName, bugType: bugType,
            category: .thermal, timestamp: timestamp ?? Date(),
            osVersion: metadata["os_version"] as? String ?? "Unknown",
            buildVersion: nil, deviceModel: product, deviceName: knowledgeBase.modelName(for: product),
            panicString: json["panicString"] as? String,
            missingSensors: [], faultingService: nil, cpuCaller: nil,
            processName: nil, bundleID: nil, exceptionType: nil, terminationReason: nil, faultingThread: nil,
            gpuRestartReason: nil, gpuSignature: nil,
            largestProcess: nil, freePages: nil, activePages: nil,
            restoreError: nil,
            rawMetadata: metadataRaw, rawBody: body, diagnosis: nil
        )
    }
}
```

- [ ] **Step 9: Build and verify**

```bash
cd /Users/samuelmuselet/Desktop/iCrashDiag && swift build 2>&1
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 10: Commit**

```bash
git add iCrashDiag/Parsing/
git commit -m "feat: parsing engine — 7 parsers for all .ips crash types"
```

---

## Task 5: Diagnosis Engine

**Files:**
- Create: `iCrashDiag/Diagnosis/DiagnosisEngine.swift`

- [ ] **Step 1: Create DiagnosisEngine.swift**

```swift
// iCrashDiag/Diagnosis/DiagnosisEngine.swift
import Foundation

final class DiagnosisEngine: Sendable {
    let knowledgeBase: KnowledgeBase

    init(knowledgeBase: KnowledgeBase) {
        self.knowledgeBase = knowledgeBase
    }

    // MARK: - Single crash diagnosis

    func diagnose(crash: CrashLog) -> Diagnosis? {
        // Build searchable text from all relevant fields
        var searchText = ""
        if let ps = crash.panicString { searchText += ps }
        if let gpr = crash.gpuRestartReason { searchText += " " + gpr }
        if !crash.missingSensors.isEmpty { searchText += " Missing sensor: " + crash.missingSensors.joined(separator: ", ") }
        if let fs = crash.faultingService { searchText += " " + fs }
        if crash.category == .jetsam { searchText += " JetsamEvent" }

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

    // MARK: - Aggregate analysis

    func analyzeAll(crashes: [CrashLog]) -> AnalysisReport {
        // Diagnose each crash
        var diagnosedCrashes = crashes
        for i in diagnosedCrashes.indices {
            diagnosedCrashes[i].diagnosis = diagnose(crash: diagnosedCrashes[i])
        }

        let total = diagnosedCrashes.count

        // Date range
        let dates = diagnosedCrashes.map(\.timestamp).sorted()
        let dateRange: DateRange? = dates.count >= 2 ? DateRange(start: dates.first!, end: dates.last!) : nil

        // Device models
        var deviceModels: [String: Int] = [:]
        for c in diagnosedCrashes {
            let name = c.deviceName ?? c.deviceModel
            deviceModels[name, default: 0] += 1
        }

        // OS versions
        var osVersions: [String: Int] = [:]
        for c in diagnosedCrashes { osVersions[c.osVersion, default: 0] += 1 }

        // Category breakdown
        var categoryBreakdown: [String: Int] = [:]
        for c in diagnosedCrashes { categoryBreakdown[c.category.rawValue, default: 0] += 1 }

        // Pattern frequency
        var patternCounts: [String: (PatternFrequency, Int)] = [:]
        for c in diagnosedCrashes {
            if let d = c.diagnosis {
                if let existing = patternCounts[d.patternID] {
                    patternCounts[d.patternID] = (existing.0, existing.1 + 1)
                } else {
                    patternCounts[d.patternID] = (
                        PatternFrequency(patternID: d.patternID, title: d.title, count: 0, severity: d.severity, component: d.component),
                        1
                    )
                }
            }
        }
        let topPatterns = patternCounts.values
            .map { PatternFrequency(patternID: $0.0.patternID, title: $0.0.title, count: $0.1, severity: $0.0.severity, component: $0.0.component) }
            .sorted { $0.count > $1.count }

        // Sensor frequency
        var sensorFrequency: [String: Int] = [:]
        for c in diagnosedCrashes {
            for s in c.missingSensors { sensorFrequency[s, default: 0] += 1 }
        }

        // Service frequency
        var serviceFrequency: [String: Int] = [:]
        for c in diagnosedCrashes {
            if let s = c.faultingService { serviceFrequency[s, default: 0] += 1 }
        }

        // Crashes per day
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        var crashesPerDay: [String: Int] = [:]
        for c in diagnosedCrashes { crashesPerDay[dayFormatter.string(from: c.timestamp), default: 0] += 1 }

        // Dominant diagnosis
        let dominant = topPatterns.first.flatMap { top in
            diagnosedCrashes.first(where: { $0.diagnosis?.patternID == top.patternID })?.diagnosis
        }

        // Verdict
        let hardwareCount = diagnosedCrashes.filter { $0.diagnosis?.severity == .hardware || $0.diagnosis?.severity == .critical }.count
        let hardwareRatio = total > 0 ? Double(hardwareCount) / Double(total) : 0
        let isHardware = hardwareRatio > 0.5
        let confidence = applyConfidenceModifiers(baseConfidence: dominant?.confidencePercent ?? 50, totalCrashes: total, topPattern: topPatterns.first, totalPatterns: topPatterns.count)

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

    // MARK: - Confidence modifiers

    private func applyConfidenceModifiers(baseConfidence: Int, totalCrashes: Int, topPattern: PatternFrequency?, totalPatterns: Int) -> Int {
        var confidence = baseConfidence

        // Consistency bonus: same pattern 10+ times
        if let top = topPattern, top.count >= 10 { confidence += 5 }

        // Cap at base max for 50+ crashes
        if let top = topPattern, top.count >= 50 { confidence = min(confidence, baseConfidence) }

        // Mixed signals: multiple different patterns
        if totalPatterns > 3 { confidence -= 10 }

        // Single occurrence penalty
        if totalCrashes == 1 { confidence -= 15 }

        // Model match bonus handled in diagnose() — skip here

        return max(0, min(100, confidence))
    }
}
```

- [ ] **Step 2: Build and verify**

```bash
cd /Users/samuelmuselet/Desktop/iCrashDiag && swift build 2>&1
```

- [ ] **Step 3: Commit**

```bash
git add iCrashDiag/Diagnosis/
git commit -m "feat: diagnosis engine — pattern matching, confidence scoring, aggregate analysis"
```

---

## Task 6: Export Service

**Files:**
- Create: `iCrashDiag/Services/ExportService.swift`

- [ ] **Step 1: Create ExportService.swift**

```swift
// iCrashDiag/Services/ExportService.swift
import Foundation

struct ExportService {

    // MARK: - Markdown report (for clipboard and file)

    func generateMarkdown(crashes: [CrashLog], report: AnalysisReport) -> String {
        var md = ""

        // Header
        let deviceName = report.deviceModels.max(by: { $0.value < $1.value })?.key ?? "Unknown Device"
        md += "# iCrashDiag Report — \(deviceName)\n\n"

        // Summary
        md += "## Summary\n"
        md += "- **Device**: \(deviceName)\n"
        if let os = report.osVersions.max(by: { $0.value < $1.value })?.key {
            md += "- **iOS**: \(os)\n"
        }
        if let dr = report.dateRange {
            let fmt = DateFormatter()
            fmt.dateStyle = .medium
            md += "- **Period**: \(fmt.string(from: dr.start)) — \(fmt.string(from: dr.end))\n"
        }
        md += "- **Total crashes**: \(report.totalCrashes)"
        let cats = report.categoryBreakdown.sorted { $0.value > $1.value }
        if !cats.isEmpty {
            md += " (" + cats.map { "\($0.value) \($0.key)" }.joined(separator: ", ") + ")"
        }
        md += "\n"
        let verdict = report.overallVerdict
        md += "- **Verdict**: \(verdict.isHardware ? "HARDWARE ISSUE" : "SOFTWARE / NORMAL") — \(verdict.confidence)% confidence\n\n"

        // Primary diagnosis
        if let diag = report.dominantDiagnosis, let top = report.topPatterns.first {
            md += "## Primary Diagnosis\n"
            md += "**\(diag.title)**\n\n"
            md += "\(top.count)/\(report.totalCrashes) crashes — \(diag.component)\n\n"

            md += "### Probabilities\n"
            for p in diag.probabilities {
                md += "- \(p.percent)% — \(p.cause)\n"
            }
            md += "\n"

            md += "### Recommended Repair\n"
            for step in diag.repairSteps {
                md += "\(step)\n"
            }
            md += "\n"

            md += "### Test Procedure\n"
            for test in diag.testProcedure {
                md += "- \(test)\n"
            }
            md += "\n"
        }

        // Timeline
        if !report.crashesPerDay.isEmpty {
            md += "## Timeline\n"
            md += "| Date | Crashes |\n|------|--------|\n"
            for day in report.crashesPerDay.keys.sorted() {
                md += "| \(day) | \(report.crashesPerDay[day]!) |\n"
            }
            md += "\n"
        }

        // All patterns
        if !report.topPatterns.isEmpty {
            md += "## All Patterns Detected\n"
            md += "| Pattern | Count | Severity | Component |\n|---------|-------|----------|----------|\n"
            for p in report.topPatterns {
                md += "| \(p.title) | \(p.count) | \(p.severity.label) | \(p.component) |\n"
            }
            md += "\n"
        }

        // Missing sensors
        if !report.sensorFrequency.isEmpty {
            md += "## Missing Sensors\n"
            for (sensor, count) in report.sensorFrequency.sorted(by: { $0.value > $1.value }) {
                md += "- **\(sensor)**: \(count) occurrences\n"
            }
            md += "\n"
        }

        md += "---\nGenerated by iCrashDiag v1.0\n"
        return md
    }

    // MARK: - JSON export

    func generateJSON(crashes: [CrashLog], report: AnalysisReport) throws -> Data {
        let export = ExportPayload(
            generatedAt: Date(),
            appVersion: "1.0",
            report: report,
            crashes: crashes
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(export)
    }
}

struct ExportPayload: Codable {
    let generatedAt: Date
    let appVersion: String
    let report: AnalysisReport
    let crashes: [CrashLog]
}
```

- [ ] **Step 2: Build and verify**

```bash
cd /Users/samuelmuselet/Desktop/iCrashDiag && swift build 2>&1
```

- [ ] **Step 3: Commit**

```bash
git add iCrashDiag/Services/ExportService.swift
git commit -m "feat: export service — Markdown + JSON report generation"
```

---

## Task 7: USB Device Service

**Files:**
- Create: `iCrashDiag/Services/USBDeviceService.swift`

- [ ] **Step 1: Create USBDeviceService.swift**

```swift
// iCrashDiag/Services/USBDeviceService.swift
import Foundation

struct DeviceInfo: Sendable {
    let udid: String
    let name: String
    let productType: String
    let modelName: String?
}

final class USBDeviceService: Sendable {

    var isAvailable: Bool {
        let result = run(command: "which", arguments: ["idevicecrashreport"])
        return result.exitCode == 0
    }

    func listDevices() -> [String] {
        let result = run(command: "idevice_id", arguments: ["-l"])
        guard result.exitCode == 0 else { return [] }
        return result.output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    func deviceInfo(udid: String, knowledgeBase: KnowledgeBase) -> DeviceInfo? {
        let nameResult = run(command: "ideviceinfo", arguments: ["-u", udid, "-k", "DeviceName"])
        let typeResult = run(command: "ideviceinfo", arguments: ["-u", udid, "-k", "ProductType"])
        guard nameResult.exitCode == 0, typeResult.exitCode == 0 else { return nil }

        let name = nameResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let productType = typeResult.output.trimmingCharacters(in: .whitespacesAndNewlines)

        return DeviceInfo(
            udid: udid,
            name: name,
            productType: productType,
            modelName: knowledgeBase.modelName(for: productType)
        )
    }

    func extractCrashLogs(to directory: URL) -> (success: Bool, output: String) {
        let result = run(command: "idevicecrashreport", arguments: ["-e", directory.path])
        return (result.exitCode == 0, result.output + result.error)
    }

    // MARK: - Private

    private struct ProcessResult: Sendable {
        let exitCode: Int32
        let output: String
        let error: String
    }

    private func run(command: String, arguments: [String]) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ProcessResult(exitCode: -1, output: "", error: error.localizedDescription)
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return ProcessResult(
            exitCode: process.terminationStatus,
            output: String(data: outData, encoding: .utf8) ?? "",
            error: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
```

- [ ] **Step 2: Build and verify**

```bash
cd /Users/samuelmuselet/Desktop/iCrashDiag && swift build 2>&1
```

- [ ] **Step 3: Commit**

```bash
git add iCrashDiag/Services/USBDeviceService.swift
git commit -m "feat: USB device service — libimobiledevice integration via Process"
```

---

## Task 8: AppViewModel (Full State Management)

**Files:**
- Modify: `iCrashDiag/ViewModels/AppViewModel.swift`

- [ ] **Step 1: Replace AppViewModel with full implementation**

```swift
// iCrashDiag/ViewModels/AppViewModel.swift
import SwiftUI

enum ExportFormat {
    case markdown, json, both
}

@Observable
@MainActor
final class AppViewModel {
    // State
    var crashLogs: [CrashLog] = []
    var selectedCrashID: UUID?
    var selectedCategory: CrashCategory?
    var selectedSeverity: Severity?
    var searchText = ""
    var sortOrder: SortOrder = .dateDescending
    var analysisReport: AnalysisReport?
    var isLoading = false
    var loadingProgress: Double = 0
    var loadingMessage = ""
    var usbAvailable = false
    var connectedDevice: DeviceInfo?
    var errorMessage: String?

    // Services
    let knowledgeBase = KnowledgeBase()
    private(set) lazy var parserEngine = CrashParserEngine(knowledgeBase: knowledgeBase)
    private(set) lazy var diagnosisEngine = DiagnosisEngine(knowledgeBase: knowledgeBase)
    let usbService = USBDeviceService()
    let exportService = ExportService()

    // Computed
    var filteredCrashLogs: [CrashLog] {
        var logs = crashLogs

        if let cat = selectedCategory {
            logs = logs.filter { $0.category == cat }
        }
        if let sev = selectedSeverity {
            logs = logs.filter { $0.diagnosis?.severity == sev }
        }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            logs = logs.filter { crash in
                crash.fileName.lowercased().contains(query) ||
                crash.category.rawValue.lowercased().contains(query) ||
                (crash.diagnosis?.title.lowercased().contains(query) ?? false) ||
                crash.missingSensors.joined(separator: " ").lowercased().contains(query) ||
                (crash.faultingService?.lowercased().contains(query) ?? false) ||
                (crash.processName?.lowercased().contains(query) ?? false)
            }
        }

        switch sortOrder {
        case .dateDescending: logs.sort { $0.timestamp > $1.timestamp }
        case .dateAscending: logs.sort { $0.timestamp < $1.timestamp }
        case .severity:
            let order: [Severity] = [.critical, .hardware, .software, .informational]
            logs.sort { a, b in
                let ai = order.firstIndex(of: a.diagnosis?.severity ?? .informational) ?? 3
                let bi = order.firstIndex(of: b.diagnosis?.severity ?? .informational) ?? 3
                return ai < bi
            }
        case .category: logs.sort { $0.category.rawValue < $1.category.rawValue }
        }
        return logs
    }

    var selectedCrash: CrashLog? {
        crashLogs.first { $0.id == selectedCrashID }
    }

    var categoryCounters: [(CrashCategory, Int)] {
        var counts: [CrashCategory: Int] = [:]
        for c in crashLogs { counts[c.category, default: 0] += 1 }
        return CrashCategory.allCases.compactMap { cat in
            guard let count = counts[cat] else { return nil }
            return (cat, count)
        }
    }

    var severityCounters: [(Severity, Int)] {
        var counts: [Severity: Int] = [:]
        for c in crashLogs {
            let sev = c.diagnosis?.severity ?? .informational
            counts[sev, default: 0] += 1
        }
        return Severity.allCases.compactMap { sev in
            guard let count = counts[sev] else { return nil }
            return (sev, count)
        }
    }

    // MARK: - Actions

    func importFolder(url: URL) async {
        isLoading = true
        loadingMessage = "Scanning for .ips files..."
        loadingProgress = 0

        let results = await parserEngine.parseDirectory(url: url) { [weak self] progress, message in
            Task { @MainActor in
                self?.loadingProgress = progress
                self?.loadingMessage = message
            }
        }

        crashLogs = results
        // Diagnose all
        for i in crashLogs.indices {
            crashLogs[i].diagnosis = diagnosisEngine.diagnose(crash: crashLogs[i])
        }
        analysisReport = diagnosisEngine.analyzeAll(crashes: crashLogs)

        isLoading = false
        loadingMessage = "Loaded \(crashLogs.count) crash logs"
    }

    func pullFromUSB() async {
        guard usbService.isAvailable else {
            errorMessage = "libimobiledevice not found. Install with: brew install libimobiledevice"
            return
        }

        let devices = usbService.listDevices()
        guard let udid = devices.first else {
            errorMessage = "No iPhone detected. Connect via USB cable."
            return
        }

        connectedDevice = usbService.deviceInfo(udid: udid, knowledgeBase: knowledgeBase)
        isLoading = true
        loadingMessage = "Extracting crash logs from \(connectedDevice?.name ?? "iPhone")..."

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("iCrashDiag-extract-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let result = usbService.extractCrashLogs(to: tempDir)
        if result.success {
            await importFolder(url: tempDir)
        } else {
            errorMessage = "USB extraction failed: \(result.output)"
            isLoading = false
        }
    }

    func copyReportToClipboard() {
        guard let report = analysisReport else { return }
        let md = exportService.generateMarkdown(crashes: crashLogs, report: report)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)
    }

    func checkUSBAvailability() {
        usbAvailable = usbService.isAvailable
    }
}
```

- [ ] **Step 2: Build and verify**

```bash
cd /Users/samuelmuselet/Desktop/iCrashDiag && swift build 2>&1
```

- [ ] **Step 3: Commit**

```bash
git add iCrashDiag/ViewModels/AppViewModel.swift
git commit -m "feat: AppViewModel — full state management, import, USB, export actions"
```

---

## Task 9: Shared View Components

**Files:**
- Create: `iCrashDiag/Views/Shared/SeverityBadge.swift`
- Create: `iCrashDiag/Views/Shared/CategoryBadge.swift`

- [ ] **Step 1: Create SeverityBadge.swift**

```swift
// iCrashDiag/Views/Shared/SeverityBadge.swift
import SwiftUI

struct SeverityBadge: View {
    let severity: Severity

    var body: some View {
        Text(severity.label)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch severity {
        case .critical: .red
        case .hardware: .orange
        case .software: .yellow
        case .informational: .secondary
        }
    }
}
```

- [ ] **Step 2: Create CategoryBadge.swift**

```swift
// iCrashDiag/Views/Shared/CategoryBadge.swift
import SwiftUI

struct CategoryBadge: View {
    let category: CrashCategory

    var body: some View {
        Label(category.rawValue, systemImage: category.systemImage)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary)
            .clipShape(Capsule())
    }
}
```

- [ ] **Step 3: Build and verify**

```bash
cd /Users/samuelmuselet/Desktop/iCrashDiag && swift build 2>&1
```

- [ ] **Step 4: Commit**

```bash
git add iCrashDiag/Views/Shared/
git commit -m "feat: shared components — SeverityBadge + CategoryBadge"
```

---

## Task 10: Sidebar View

**Files:**
- Create: `iCrashDiag/Views/Sidebar/SidebarView.swift`

- [ ] **Step 1: Create SidebarView.swift**

```swift
// iCrashDiag/Views/Sidebar/SidebarView.swift
import SwiftUI

struct SidebarView: View {
    @Environment(AppViewModel.self) private var viewModel
    @State private var showFolderPicker = false

    var body: some View {
        @Bindable var vm = viewModel

        List {
            // Import buttons
            Section {
                Button {
                    showFolderPicker = true
                } label: {
                    Label("Import Folder", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)

                Button {
                    Task { await viewModel.pullFromUSB() }
                } label: {
                    Label("Pull from iPhone", systemImage: "iphone.gen3")
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.usbAvailable)
                .help(viewModel.usbAvailable ? "Extract crash logs via USB" : "Install libimobiledevice: brew install libimobiledevice")
            }

            if !viewModel.crashLogs.isEmpty {
                // Categories
                Section("Categories") {
                    Button {
                        viewModel.selectedCategory = nil
                        viewModel.selectedSeverity = nil
                    } label: {
                        HStack {
                            Label("All", systemImage: "tray.full.fill")
                            Spacer()
                            Text("\(viewModel.crashLogs.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .fontWeight(viewModel.selectedCategory == nil ? .semibold : .regular)

                    ForEach(viewModel.categoryCounters, id: \.0) { category, count in
                        Button {
                            viewModel.selectedCategory = viewModel.selectedCategory == category ? nil : category
                        } label: {
                            HStack {
                                Label(category.rawValue, systemImage: category.systemImage)
                                Spacer()
                                Text("\(count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .fontWeight(viewModel.selectedCategory == category ? .semibold : .regular)
                    }
                }

                // Severity
                Section("Severity") {
                    ForEach(viewModel.severityCounters, id: \.0) { severity, count in
                        Button {
                            viewModel.selectedSeverity = viewModel.selectedSeverity == severity ? nil : severity
                        } label: {
                            HStack {
                                SeverityBadge(severity: severity)
                                Spacer()
                                Text("\(count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Device breakdown
                if let report = viewModel.analysisReport, report.deviceModels.count > 0 {
                    Section("Devices") {
                        ForEach(report.deviceModels.sorted(by: { $0.value > $1.value }), id: \.key) { model, count in
                            HStack {
                                Text(model)
                                    .font(.caption)
                                Spacer()
                                Text("\(count)")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                    }
                }

                // Quick stats
                if let report = viewModel.analysisReport {
                    Section("Stats") {
                        if let dr = report.dateRange {
                            let fmt = DateFormatter()
                            let _ = fmt.dateStyle = .short
                            LabeledContent("Period", value: "\(fmt.string(from: dr.start)) — \(fmt.string(from: dr.end))")
                                .font(.caption)
                        }
                        if report.totalCrashes > 0, let dr = report.dateRange {
                            let days = max(1, Calendar.current.dateComponents([.day], from: dr.start, to: dr.end).day ?? 1)
                            LabeledContent("Avg/day", value: "\(report.totalCrashes / days)")
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                Task { await viewModel.importFolder(url: url) }
            }
        }
        .onAppear {
            viewModel.checkUSBAvailability()
        }
    }
}
```

- [ ] **Step 2: Build and verify**

```bash
cd /Users/samuelmuselet/Desktop/iCrashDiag && swift build 2>&1
```

- [ ] **Step 3: Commit**

```bash
git add iCrashDiag/Views/Sidebar/
git commit -m "feat: sidebar — import buttons, category/severity filters, device stats"
```

---

## Task 11: Crash List View

**Files:**
- Create: `iCrashDiag/Views/CrashList/CrashRowView.swift`
- Create: `iCrashDiag/Views/CrashList/CrashListView.swift`

- [ ] **Step 1: Create CrashRowView.swift**

```swift
// iCrashDiag/Views/CrashList/CrashRowView.swift
import SwiftUI

struct CrashRowView: View {
    let crash: CrashLog

    var body: some View {
        HStack(spacing: 8) {
            // Severity color bar
            RoundedRectangle(cornerRadius: 2)
                .fill(severityColor)
                .frame(width: 4, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(crash.fileName)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(crash.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 4) {
                    CategoryBadge(category: crash.category)

                    if let diag = crash.diagnosis {
                        Text(diag.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if let proc = crash.processName {
                        Text(proc)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var severityColor: Color {
        guard let sev = crash.diagnosis?.severity else { return .secondary.opacity(0.3) }
        switch sev {
        case .critical: return .red
        case .hardware: return .orange
        case .software: return .yellow
        case .informational: return .secondary
        }
    }
}
```

- [ ] **Step 2: Create CrashListView.swift**

```swift
// iCrashDiag/Views/CrashList/CrashListView.swift
import SwiftUI

struct CrashListView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel

        List(viewModel.filteredCrashLogs, selection: $vm.selectedCrashID) { crash in
            CrashRowView(crash: crash)
                .tag(crash.id)
        }
        .searchable(text: $vm.searchText, prompt: "Search crashes...")
        .toolbar {
            ToolbarItem {
                Picker("Sort", selection: $vm.sortOrder) {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .overlay {
            if viewModel.crashLogs.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "No Crash Logs",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Import a folder or pull from an iPhone to get started.")
                )
            }
            if viewModel.isLoading {
                VStack(spacing: 12) {
                    ProgressView(value: viewModel.loadingProgress)
                        .frame(width: 200)
                    Text(viewModel.loadingMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}
```

- [ ] **Step 3: Build and verify**

```bash
cd /Users/samuelmuselet/Desktop/iCrashDiag && swift build 2>&1
```

- [ ] **Step 4: Commit**

```bash
git add iCrashDiag/Views/CrashList/
git commit -m "feat: crash list — searchable sorted list with severity-coded rows"
```

---

## Task 12: Detail Panel Views

**Files:**
- Create: `iCrashDiag/Views/Detail/DiagnosisCardView.swift`
- Create: `iCrashDiag/Views/Detail/ProbabilityBarsView.swift`
- Create: `iCrashDiag/Views/Detail/RawPanicView.swift`
- Create: `iCrashDiag/Views/Detail/CrashDetailView.swift`

- [ ] **Step 1: Create DiagnosisCardView.swift**

```swift
// iCrashDiag/Views/Detail/DiagnosisCardView.swift
import SwiftUI

struct DiagnosisCardView: View {
    let diagnosis: Diagnosis

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SeverityBadge(severity: diagnosis.severity)
                Text("\(diagnosis.confidencePercent)% confidence")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(diagnosis.title)
                .font(.headline)

            Text(diagnosis.component)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(severityColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(severityColor.opacity(0.3), lineWidth: 1)
                )
        }
    }

    private var severityColor: Color {
        switch diagnosis.severity {
        case .critical: .red
        case .hardware: .orange
        case .software: .yellow
        case .informational: .secondary
        }
    }
}
```

- [ ] **Step 2: Create ProbabilityBarsView.swift**

```swift
// iCrashDiag/Views/Detail/ProbabilityBarsView.swift
import SwiftUI

struct ProbabilityBarsView: View {
    let probabilities: [Probability]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Probabilities")
                .font(.subheadline)
                .fontWeight(.semibold)

            ForEach(Array(probabilities.enumerated()), id: \.offset) { _, prob in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("\(prob.percent)%")
                            .font(.caption)
                            .fontWeight(.bold)
                            .frame(width: 36, alignment: .trailing)
                            .monospacedDigit()

                        Text(prob.cause)
                            .font(.caption)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.quaternary)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.orange.gradient)
                                .frame(width: geo.size.width * CGFloat(prob.percent) / 100)
                        }
                    }
                    .frame(height: 6)

                    Text(prob.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
```

- [ ] **Step 3: Create RawPanicView.swift**

```swift
// iCrashDiag/Views/Detail/RawPanicView.swift
import SwiftUI

struct RawPanicView: View {
    let text: String
    let highlights: [String]

    var body: some View {
        ScrollView {
            Text(attributedText)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .background(.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var attributedText: AttributedString {
        var attr = AttributedString(text)
        for keyword in highlights {
            var searchRange = attr.startIndex..<attr.endIndex
            while let range = attr[searchRange].range(of: keyword, options: .caseInsensitive) {
                attr[range].foregroundColor = .red
                attr[range].font = .system(.caption, design: .monospaced).bold()
                searchRange = range.upperBound..<attr.endIndex
            }
        }
        return attr
    }
}
```

- [ ] **Step 4: Create CrashDetailView.swift**

```swift
// iCrashDiag/Views/Detail/CrashDetailView.swift
import SwiftUI

struct CrashDetailView: View {
    let crash: CrashLog
    @Environment(AppViewModel.self) private var viewModel
    @State private var showRaw = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Diagnosis card
                if let diag = crash.diagnosis {
                    DiagnosisCardView(diagnosis: diag)
                    ProbabilityBarsView(probabilities: diag.probabilities)

                    // Repair steps
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Repair Steps")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        ForEach(diag.repairSteps, id: \.self) { step in
                            Text(step)
                                .font(.caption)
                        }
                    }

                    // Test procedure
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Test Procedure")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        ForEach(diag.testProcedure, id: \.self) { test in
                            Label(test, systemImage: "checkmark.circle")
                                .font(.caption)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("No known pattern detected", systemImage: "questionmark.circle")
                            .font(.headline)
                        Text("Export the raw data for analysis with an AI tool.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                }

                Divider()

                // Device info
                VStack(alignment: .leading, spacing: 4) {
                    Text("Device Info")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    LabeledContent("Model", value: crash.deviceName ?? crash.deviceModel)
                    LabeledContent("iOS", value: crash.osVersion)
                    LabeledContent("Date", value: crash.timestamp.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("File", value: crash.fileName)
                    LabeledContent("Bug Type", value: "\(crash.bugType)")

                    if !crash.missingSensors.isEmpty {
                        LabeledContent("Missing Sensors", value: crash.missingSensors.joined(separator: ", "))
                    }
                    if let fs = crash.faultingService {
                        LabeledContent("Faulting Service", value: fs)
                    }
                    if let proc = crash.processName {
                        LabeledContent("Process", value: proc)
                    }
                    if let exc = crash.exceptionType {
                        LabeledContent("Exception", value: exc)
                    }
                    if let gpu = crash.gpuRestartReason {
                        LabeledContent("GPU Reason", value: gpu)
                    }
                    if let err = crash.restoreError {
                        LabeledContent("Restore Error", value: "\(err)")
                    }
                    if let lp = crash.largestProcess {
                        LabeledContent("Largest Process", value: lp)
                    }
                }
                .font(.caption)

                Divider()

                // Action buttons
                HStack {
                    Button("Copy Report") {
                        copySingleCrashReport()
                    }
                    .buttonStyle(.bordered)

                    Button(showRaw ? "Hide Raw Data" : "Show Raw Data") {
                        showRaw.toggle()
                    }
                    .buttonStyle(.bordered)
                }

                // Raw data
                if showRaw {
                    let highlights = crash.missingSensors + [crash.faultingService].compactMap { $0 }
                    RawPanicView(
                        text: crash.panicString ?? crash.rawBody,
                        highlights: highlights
                    )
                    .frame(minHeight: 200, maxHeight: 400)
                }
            }
            .padding()
        }
    }

    private func copySingleCrashReport() {
        var md = "# Crash Report: \(crash.fileName)\n\n"
        md += "- **Category**: \(crash.category.rawValue)\n"
        md += "- **Device**: \(crash.deviceName ?? crash.deviceModel)\n"
        md += "- **iOS**: \(crash.osVersion)\n"
        md += "- **Date**: \(crash.timestamp.formatted())\n\n"

        if let diag = crash.diagnosis {
            md += "## Diagnosis\n"
            md += "**\(diag.title)** — \(diag.confidencePercent)% confidence\n"
            md += "Component: \(diag.component)\n\n"
            for p in diag.probabilities {
                md += "- \(p.percent)% — \(p.cause)\n"
            }
            md += "\n### Repair\n"
            for s in diag.repairSteps { md += "\(s)\n" }
        }

        if let ps = crash.panicString {
            md += "\n## Raw Panic String\n```\n\(ps)\n```\n"
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)
    }
}
```

- [ ] **Step 5: Build and verify**

```bash
cd /Users/samuelmuselet/Desktop/iCrashDiag && swift build 2>&1
```

- [ ] **Step 6: Commit**

```bash
git add iCrashDiag/Views/Detail/
git commit -m "feat: detail panel — diagnosis card, probability bars, raw data, repair steps"
```

---

## Task 13: Overview + Timeline Chart

**Files:**
- Create: `iCrashDiag/Views/Overview/TimelineChartView.swift`
- Create: `iCrashDiag/Views/Overview/OverviewView.swift`

- [ ] **Step 1: Create TimelineChartView.swift**

```swift
// iCrashDiag/Views/Overview/TimelineChartView.swift
import SwiftUI
import Charts

struct TimelineChartView: View {
    let crashesPerDay: [String: Int]

    var body: some View {
        let data = crashesPerDay.sorted(by: { $0.key < $1.key })

        Chart(data, id: \.key) { day, count in
            BarMark(
                x: .value("Date", day),
                y: .value("Crashes", count)
            )
            .foregroundStyle(.orange.gradient)
        }
        .chartYAxisLabel("Crashes")
        .frame(height: 180)
    }
}
```

- [ ] **Step 2: Create OverviewView.swift**

```swift
// iCrashDiag/Views/Overview/OverviewView.swift
import SwiftUI

struct OverviewView: View {
    let report: AnalysisReport
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Verdict banner
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: report.overallVerdict.isHardware ? "wrench.and.screwdriver.fill" : "checkmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(report.overallVerdict.isHardware ? .orange : .green)
                        VStack(alignment: .leading) {
                            Text(report.overallVerdict.isHardware ? "HARDWARE ISSUE DETECTED" : "NO HARDWARE ISSUE")
                                .font(.headline)
                            Text("\(report.overallVerdict.confidence)% confidence")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(report.overallVerdict.summary)
                        .font(.subheadline)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(report.overallVerdict.isHardware ? .orange.opacity(0.1) : .green.opacity(0.1))
                )

                // Primary diagnosis
                if let diag = report.dominantDiagnosis {
                    DiagnosisCardView(diagnosis: diag)
                }

                // Stats row
                HStack(spacing: 16) {
                    StatCard(title: "Total Crashes", value: "\(report.totalCrashes)", icon: "doc.text.fill")
                    if let dr = report.dateRange {
                        let days = max(1, Calendar.current.dateComponents([.day], from: dr.start, to: dr.end).day ?? 1)
                        StatCard(title: "Per Day", value: "\(report.totalCrashes / days)", icon: "calendar")
                    }
                    StatCard(title: "Patterns", value: "\(report.topPatterns.count)", icon: "magnifyingglass")
                }

                // Timeline
                if !report.crashesPerDay.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Timeline")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        TimelineChartView(crashesPerDay: report.crashesPerDay)
                    }
                }

                // Top patterns table
                if !report.topPatterns.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Detected Patterns")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        ForEach(report.topPatterns) { pattern in
                            HStack {
                                SeverityBadge(severity: pattern.severity)
                                Text(pattern.title)
                                    .font(.caption)
                                Spacer()
                                Text("\(pattern.count)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .monospacedDigit()
                                Text(pattern.component)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                // Export buttons
                HStack {
                    Button("Copy Full Report") {
                        viewModel.copyReportToClipboard()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Export JSON...") {
                        exportJSON()
                    }
                    .buttonStyle(.bordered)

                    Button("Export Markdown...") {
                        exportMarkdown()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
    }

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "iCrashDiag-report.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let data = try? viewModel.exportService.generateJSON(crashes: viewModel.crashLogs, report: report) {
            try? data.write(to: url)
        }
    }

    private func exportMarkdown() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "iCrashDiag-report.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let md = viewModel.exportService.generateMarkdown(crashes: viewModel.crashLogs, report: report)
        try? md.write(to: url, atomically: true, encoding: .utf8)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .monospacedDigit()
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}
```

- [ ] **Step 3: Build and verify**

```bash
cd /Users/samuelmuselet/Desktop/iCrashDiag && swift build 2>&1
```

- [ ] **Step 4: Commit**

```bash
git add iCrashDiag/Views/Overview/
git commit -m "feat: overview — verdict banner, timeline chart, pattern table, export buttons"
```

---

## Task 14: Wire Up ContentView

**Files:**
- Modify: `iCrashDiag/ContentView.swift`

- [ ] **Step 1: Replace ContentView with full 3-column layout**

```swift
// iCrashDiag/ContentView.swift
import SwiftUI

struct ContentView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel

        NavigationSplitView {
            SidebarView()
        } content: {
            CrashListView()
        } detail: {
            if let crash = viewModel.selectedCrash {
                CrashDetailView(crash: crash)
            } else if let report = viewModel.analysisReport {
                OverviewView(report: report)
            } else {
                ContentUnavailableView(
                    "iCrashDiag",
                    systemImage: "iphone.gen3.radiowaves.left.and.right",
                    description: Text("Import crash logs to begin diagnosis")
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle("iCrashDiag")
        .toolbar {
            if let report = viewModel.analysisReport {
                ToolbarItem {
                    Button {
                        viewModel.selectedCrashID = nil
                    } label: {
                        Label("Overview", systemImage: "chart.bar.doc.horizontal")
                    }
                    .help("Show overview report")
                }

                ToolbarItem {
                    Text("KB v\(viewModel.knowledgeBase.version)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}
```

- [ ] **Step 2: Build and verify**

```bash
cd /Users/samuelmuselet/Desktop/iCrashDiag && swift build 2>&1
```

- [ ] **Step 3: Commit**

```bash
git add iCrashDiag/ContentView.swift
git commit -m "feat: wire up ContentView — 3-column layout with sidebar, list, detail/overview"
```

---

## Task 15: Knowledge Base Auto-Update

**Files:**
- Create: `iCrashDiag/Knowledge/KnowledgeBaseManager.swift`

- [ ] **Step 1: Create KnowledgeBaseManager.swift**

```swift
// iCrashDiag/Knowledge/KnowledgeBaseManager.swift
import Foundation

actor KnowledgeBaseManager {
    private let remoteBaseURL: URL
    private let localDir: URL
    private let files = ["version.json", "panic-patterns.json", "iphone-models.json", "components.json"]

    init(repoOwner: String = "ateliersam86", repoName: String = "iCrashDiag") {
        self.remoteBaseURL = URL(string: "https://raw.githubusercontent.com/\(repoOwner)/\(repoName)/main/knowledge/")!
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.localDir = appSupport.appendingPathComponent("iCrashDiag/knowledge")
    }

    func checkForUpdates(currentVersion: String) async -> Bool {
        do {
            let versionURL = remoteBaseURL.appendingPathComponent("version.json")
            let (data, _) = try await URLSession.shared.data(from: versionURL)
            let remote = try JSONDecoder().decode(VersionFile.self, from: data)

            if remote.version > currentVersion {
                try await downloadAll()
                return true
            }
        } catch {
            // Silently fail — use bundled/cached version
        }
        return false
    }

    private func downloadAll() async throws {
        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)

        for file in files {
            let url = remoteBaseURL.appendingPathComponent(file)
            let (data, _) = try await URLSession.shared.data(from: url)
            try data.write(to: localDir.appendingPathComponent(file))
        }
    }
}
```

- [ ] **Step 2: Add auto-update call to AppViewModel.init or onAppear**

In `iCrashDiagApp.swift`, add an `.onAppear` or `.task` to trigger the check:

Update `iCrashDiagApp.swift`:

```swift
// iCrashDiag/iCrashDiagApp.swift
import SwiftUI

@main
struct iCrashDiagApp: App {
    @State private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(viewModel)
                .task {
                    let manager = KnowledgeBaseManager()
                    let _ = await manager.checkForUpdates(currentVersion: viewModel.knowledgeBase.version)
                }
        }
        .defaultSize(width: 1200, height: 750)
    }
}
```

- [ ] **Step 3: Build and verify**

```bash
cd /Users/samuelmuselet/Desktop/iCrashDiag && swift build 2>&1
```

- [ ] **Step 4: Commit**

```bash
git add iCrashDiag/Knowledge/KnowledgeBaseManager.swift iCrashDiag/iCrashDiagApp.swift
git commit -m "feat: knowledge base auto-update from GitHub on launch"
```

---

## Task 16: Build, Run, and Verify with Test Data

- [ ] **Step 1: Full clean build**

```bash
cd /Users/samuelmuselet/Desktop/iCrashDiag && swift build 2>&1
```

Fix any compilation errors. Expected: BUILD SUCCEEDED with zero errors.

- [ ] **Step 2: Run the app**

Use XcodeBuildMCP or `swift run` to launch:

```bash
cd /Users/samuelmuselet/Desktop/iCrashDiag && swift run &
```

The app window should open with a 3-column layout.

- [ ] **Step 3: Test with real crash data**

Open the app, click "Import Folder", select `/Users/samuelmuselet/Desktop/iPhone-CrashLogs/`.

Verify:
- All 369 files parsed (status bar shows count)
- Sidebar shows category breakdown (261 Kernel Panic, 61 Jetsam, etc.)
- Crash list shows sorted entries with severity color bars
- Clicking a kernel panic shows mic1_missing diagnosis at 95% confidence
- Overview shows timeline chart + verdict "HARDWARE ISSUE"
- Copy Report puts valid Markdown in clipboard
- Raw data toggle shows panic string with highlighted keywords

- [ ] **Step 4: Fix any issues found during testing**

Address any UI layout issues, parsing errors, or diagnosis mismatches.

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "fix: address issues from testing with real crash data"
```

---

## Task 17: .gitignore + README + LICENSE

**Files:**
- Create: `.gitignore`
- Create: `README.md`
- Create: `LICENSE`

- [ ] **Step 1: Create .gitignore**

```
.DS_Store
.build/
*.xcodeproj/xcuserdata/
DerivedData/
.swiftpm/
```

- [ ] **Step 2: Create README.md**

```markdown
# iCrashDiag

Native macOS app for iPhone crash log analysis. Built for repair technicians.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 6](https://img.shields.io/badge/Swift-6-orange)
![License: MIT](https://img.shields.io/badge/License-MIT-green)

## Features

- **Import** crash logs from folder or USB-connected iPhone
- **Parse** all .ips file types: kernel panics, thermal events, Jetsam, app crashes, GPU events, OTA failures
- **Diagnose** hardware vs software issues with confidence scores
- **Repair guidance** with step-by-step instructions and test procedures
- **Timeline** visualization of crash frequency
- **Export** reports as Markdown or JSON for external analysis
- **Auto-updating knowledge base** — new iPhone models and patterns without app update

## Requirements

- macOS 14 (Sonoma) or later
- Optional: [libimobiledevice](https://libimobiledevice.org/) for USB extraction
  ```
  brew install libimobiledevice
  ```

## Build

```bash
swift build
swift run
```

Or open in Xcode:
```bash
open Package.swift
```

## Knowledge Base

The knowledge base lives in `knowledge/` as JSON files. Contributions welcome:

- `iphone-models.json` — iPhone model identifiers → names, chips, sensors
- `panic-patterns.json` — crash patterns → diagnoses, repair steps
- `components.json` — hardware components → repair difficulty, time estimates

The app auto-updates from this repo on launch.

## License

MIT
```

- [ ] **Step 3: Create LICENSE**

Standard MIT license text with "Copyright (c) 2026 iCrashDiag contributors".

- [ ] **Step 4: Commit**

```bash
git add .gitignore README.md LICENSE
git commit -m "docs: README, LICENSE, .gitignore"
```
