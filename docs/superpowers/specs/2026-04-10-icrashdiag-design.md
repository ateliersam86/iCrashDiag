# iCrashDiag — Design Specification

## Overview

Native macOS SwiftUI app for iPhone crash log analysis, targeting repair technicians. Open source on GitHub.

Reads `.ips` crash files from USB-connected iPhones (via libimobiledevice CLI) or folder import. Parses all crash types (kernel panics, thermal events, Jetsam, app crashes, GPU events, OTA failures). Produces hardware vs software diagnoses with confidence scores, component mapping, and repair recommendations.

**Target users:** Independent repair technicians, Apple-certified repair shops, refurbishment teams.

**Market gap:** No macOS-native tool exists. Competitors are Windows-only (iDeviceLogAnalyzer), iOS-only (PanicFix), or CLI scripts.

---

## Architecture

**Approach:** Pure SwiftUI (macOS 14+) + libimobiledevice via `Process()` + JSON knowledge base with auto-update.

### Core Principles

1. **Zero hard dependencies** — App works without libimobiledevice (USB greyed out, folder import works)
2. **No database** — In-memory data model, re-parsed on each import. Lightweight JSON session cache in `~/Library/Application Support/iCrashDiag/`
3. **Auto-updating knowledge base** — JSON files bundled in app + remote update from GitHub raw + local override directory
4. **Export-first** — Every analysis exportable as Markdown (clipboard) and JSON+Markdown (file) for external AI analysis

### Tech Stack

| Layer | Choice | Reason |
|-------|--------|--------|
| UI | SwiftUI, macOS 14+ | NavigationSplitView, Inspector, native feel |
| Language | Swift 6 | Strict concurrency, Codable, async/await |
| USB | libimobiledevice CLI via Process | No C binding, optional dependency |
| Parsing | Foundation JSONSerialization + regex | .ips files are JSON line 1 + body |
| Knowledge base | JSON in bundle + remote update | Updatable without app rebuild |
| Distribution | GitHub Releases (.dmg) + Homebrew cask | Standard macOS distribution |

---

## Data Model

### CrashLog

```swift
struct CrashLog: Identifiable, Codable {
    let id: UUID
    let fileName: String
    let bugType: Int                    // 210, 298, 308, 309, 183, 284, 313, 409
    let category: CrashCategory        // .kernelPanic, .jetsam, .appCrash, .gpuEvent, .otaUpdate, .thermal, .watchdog
    let timestamp: Date
    let osVersion: String              // "iPhone OS 18.3.1 (22D63)"
    let buildVersion: String?
    let deviceModel: String            // "iPhone12,8"
    let deviceName: String?            // "iPhone SE (2nd gen)" — resolved from knowledge base

    // Panic-specific
    let panicString: String?
    let missingSensors: [String]       // ["mic1", "als"]
    let faultingService: String?       // "thermalmonitord"
    let cpuCaller: String?             // "cpu 3 caller 0x..."

    // App crash-specific
    let processName: String?           // "MobileSafari"
    let bundleID: String?
    let exceptionType: String?         // "EXC_CRASH", "EXC_GUARD"
    let terminationReason: String?
    let faultingThread: Int?
    let threadBacktrace: [StackFrame]?

    // GPU-specific
    let gpuRestartReason: String?      // "firmware-detected lockup"
    let gpuSignature: Int?

    // Jetsam-specific
    let largestProcess: String?
    let freePages: Int?
    let activePages: Int?

    // OTA-specific
    let restoreError: Int?

    // Raw
    let rawMetadata: String            // Line 1 JSON
    let rawBody: String                // Rest of file

    // Diagnosis (computed after analysis)
    var diagnosis: Diagnosis?
}
```

### CrashCategory

```swift
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
```

### Diagnosis

```swift
struct Diagnosis: Codable {
    let patternID: String              // "mic1_missing"
    let title: String                  // "Bottom microphone sensor failure"
    let severity: Severity             // .hardware, .critical, .software, .informational
    let component: String              // "Lightning flex cable"
    let confidencePercent: Int         // 85
    let probabilities: [Probability]   // [(cause, percent, description)]
    let repairSteps: [String]
    let testProcedure: [String]
    let affectedModels: [String]       // ["iPhone12,*"]
    let relatedPatterns: [String]      // other patterns often seen together
}

enum Severity: String, Codable {
    case critical       // Board-level, may be unrepairable (SEP)
    case hardware       // Component replacement needed
    case software       // iOS bug or config issue
    case informational  // Normal system behavior (Jetsam under load)
}

struct Probability: Codable {
    let cause: String          // "Nappe lightning défectueuse"
    let percent: Int           // 85
    let description: String    // "Le capteur mic1 est sur la nappe..."
}
```

### Session (lightweight cache)

```swift
struct Session: Codable {
    let importPath: String
    let importDate: Date
    let deviceSummary: String
    let crashLogIDs: [UUID]
    let analysisReport: AnalysisReport
}
```

### AnalysisReport (aggregate)

```swift
struct AnalysisReport: Codable {
    let totalCrashes: Int
    let dateRange: ClosedRange<Date>?
    let deviceModels: [String: Int]        // model → count
    let osVersions: [String: Int]
    let categoryBreakdown: [CrashCategory: Int]
    let topPatterns: [PatternFrequency]    // sorted by count desc
    let sensorFrequency: [String: Int]     // sensor → count
    let serviceFrequency: [String: Int]    // service → count
    let crashesPerDay: [String: Int]       // "2026-04-01" → count
    let dominantDiagnosis: Diagnosis?      // most frequent pattern
    let overallVerdict: Verdict
}

struct Verdict: Codable {
    let isHardware: Bool
    let confidence: Int
    let summary: String        // "261/261 kernel panics caused by mic1 sensor — Lightning flex cable replacement required"
    let estimatedRepairCost: String?
}
```

---

## Knowledge Base

### File Structure

```
# Bundled in app
Resources/knowledge/
  ├── iphone-models.json
  ├── panic-patterns.json
  ├── crash-signatures.json
  ├── components.json
  └── version.json          # { "version": "2026.04.10", "minAppVersion": "1.0" }

# Auto-updated / user override
~/Library/Application Support/iCrashDiag/knowledge/
  └── (same files, take priority)
```

### iphone-models.json

```json
{
  "models": {
    "iPhone1,1": { "name": "iPhone 2G", "chip": "APL0098", "year": 2007 },
    "iPhone12,8": { "name": "iPhone SE (2nd gen)", "chip": "A13 Bionic", "year": 2020, "sensors": ["mic1", "mic2", "als", "prox"] },
    "iPhone17,3": { "name": "iPhone 16 Pro Max", "chip": "A18 Pro", "year": 2024, "sensors": ["mic1", "mic2", "mic3", "als", "prox", "lidar"] }
  }
}
```

### panic-patterns.json

```json
{
  "version": "2026.04",
  "patterns": [
    {
      "id": "mic1_missing",
      "keywords": ["Missing sensor(s): mic1", "Missing sensor: mic1"],
      "category": "kernelPanic",
      "component": "lightning_flex",
      "severity": "hardware",
      "confidence": 95,
      "title": "Bottom microphone thermal sensor failure",
      "diagnosis": "The mic1 NTC thermal sensor on the lightning/charging flex cable is disconnected or damaged.",
      "probabilities": [
        { "cause": "Lightning flex cable defective", "percent": 85, "description": "The NTC sensor is soldered on the flex. Flex replacement resolves." },
        { "cause": "Audio codec IC damage", "percent": 10, "description": "Codec IC (338S00509) not reading sensor. Requires micro-soldering." },
        { "cause": "NTC resistor only", "percent": 5, "description": "Standalone NTC failure. Replaceable with micro-soldering." }
      ],
      "repair_steps": [
        "1. Replace lightning/charging flex cable assembly",
        "2. Test bottom microphone in Voice Memos (record + playback)",
        "3. Verify thermal sensor reads in diagnostics",
        "4. If persists: inspect codec IC under microscope"
      ],
      "test_procedure": [
        "Voice Memos: record 10s, play back — should hear clear audio from bottom mic",
        "Phone call: speaker on mute, other party should hear you clearly",
        "Diagnostics: Settings > Privacy > Analytics > check for new panic-full logs"
      ],
      "models_affected": ["iPhone8,*", "iPhone9,*", "iPhone10,*", "iPhone11,*", "iPhone12,*", "iPhone13,*", "iPhone14,*"],
      "related_patterns": ["thermalmonitord_watchdog"]
    },
    {
      "id": "thermalmonitord_watchdog",
      "keywords": ["no successful checkins from thermalmonitord", "thermalmonitord watchdog"],
      "category": "watchdog",
      "component": "thermal_system",
      "severity": "hardware",
      "confidence": 80,
      "title": "Thermal monitoring service failure",
      "diagnosis": "thermalmonitord crashed or hung, usually due to a missing/disconnected thermal sensor.",
      "probabilities": [
        { "cause": "Disconnected thermal sensor", "percent": 70, "description": "A sensor cable is damaged or not seated. Check panic string for 'Missing sensor' to identify which." },
        { "cause": "Thermal IC failure", "percent": 20, "description": "PMU or thermal controller IC fault." },
        { "cause": "iOS software bug", "percent": 10, "description": "Rare. Check if specific to one iOS version." }
      ],
      "repair_steps": [
        "1. Identify which sensor is missing from panic string",
        "2. Map sensor to physical component (mic1=lightning flex, als=proximity flex, etc.)",
        "3. Replace the corresponding flex cable",
        "4. If no sensor identified: check all flex connections, reseat"
      ],
      "test_procedure": [
        "Monitor for recurrence over 24h after repair",
        "Check Analytics for new crash logs"
      ],
      "models_affected": ["*"],
      "related_patterns": ["mic1_missing", "als_missing", "prox_missing"]
    },
    {
      "id": "gpu_hang",
      "keywords": ["GPU Hang", "gpu hang", "firmware-detected lockup", "AGXFirmwareKextG"],
      "category": "gpuEvent",
      "component": "soc_gpu",
      "severity": "hardware",
      "confidence": 70,
      "title": "GPU firmware lockup / hang",
      "diagnosis": "The GPU core locked up, triggering a firmware reset or kernel panic.",
      "probabilities": [
        { "cause": "BGA solder joint failure", "percent": 70, "description": "Cold solder joint under SoC. Common after drop or thermal cycling." },
        { "cause": "Overheating / thermal throttle failure", "percent": 20, "description": "GPU thermal paste dried, heatsink not seated." },
        { "cause": "iOS driver bug", "percent": 10, "description": "Check if specific to one iOS version. Try DFU restore." }
      ],
      "repair_steps": [
        "1. DFU restore to rule out software",
        "2. If persists: inspect board for signs of heat damage near SoC",
        "3. Reball SoC (advanced micro-soldering, low success rate)",
        "4. Board swap may be necessary"
      ],
      "test_procedure": [
        "Run a graphics-intensive app (game or benchmark)",
        "Monitor for GPU recovery messages in console",
        "Check for visual artifacts on screen"
      ],
      "models_affected": ["*"],
      "related_patterns": []
    },
    {
      "id": "kernel_data_abort",
      "keywords": ["Data Abort", "data_abort", "kernel data abort"],
      "category": "kernelPanic",
      "component": "memory_nand",
      "severity": "hardware",
      "confidence": 60,
      "title": "Kernel data abort — invalid memory access",
      "diagnosis": "The kernel accessed an invalid memory address, causing an immediate panic.",
      "probabilities": [
        { "cause": "RAM defect", "percent": 60, "description": "LPDDR4/5 cell failure. Not repairable." },
        { "cause": "NAND corruption", "percent": 30, "description": "Flash storage read error propagated to kernel. Try DFU restore first." },
        { "cause": "iOS kernel bug", "percent": 10, "description": "Rare. Check if tied to specific iOS version." }
      ],
      "repair_steps": [
        "1. DFU restore (rule out NAND filesystem corruption)",
        "2. If persists: board-level diagnosis required",
        "3. RAM is part of SoC package — not field-repairable",
        "4. Board swap"
      ],
      "test_procedure": [
        "After DFU restore, use phone normally for 48h",
        "Run memory-intensive apps",
        "Check Analytics for recurrence"
      ],
      "models_affected": ["*"],
      "related_patterns": []
    },
    {
      "id": "watchdog_backboardd",
      "keywords": ["no successful checkins from backboardd", "backboardd watchdog"],
      "category": "watchdog",
      "component": "display_touch",
      "severity": "hardware",
      "confidence": 80,
      "title": "Display/touch service timeout",
      "diagnosis": "backboardd (display + touch input service) stopped responding.",
      "probabilities": [
        { "cause": "Display flex cable", "percent": 80, "description": "Damaged or poorly seated display flex. Check FPC connector." },
        { "cause": "FPC connector damage", "percent": 15, "description": "Connector pins bent or corroded on logic board." },
        { "cause": "Meson touch IC", "percent": 5, "description": "Touch controller IC failure. Requires micro-soldering." }
      ],
      "repair_steps": [
        "1. Reseat display flex cable",
        "2. Inspect FPC connector under microscope (bent/missing pins)",
        "3. Try known-good display",
        "4. If persists with good display: Meson IC or board issue"
      ],
      "test_procedure": [
        "Touch responsiveness test (draw app, all screen areas)",
        "3D Touch / Haptic Touch pressure test",
        "Display color/dead pixel check"
      ],
      "models_affected": ["*"],
      "related_patterns": []
    },
    {
      "id": "watchdog_wifid",
      "keywords": ["no successful checkins from wifid", "wifid watchdog"],
      "category": "watchdog",
      "component": "wifi_bt_chip",
      "severity": "hardware",
      "confidence": 70,
      "title": "WiFi/Bluetooth service failure",
      "diagnosis": "wifid stopped responding, indicating WiFi/BT chip communication failure.",
      "probabilities": [
        { "cause": "WiFi/BT chip defect", "percent": 70, "description": "USI 339S00648 or similar. Common after water damage." },
        { "cause": "Antenna disconnected", "percent": 20, "description": "WiFi antenna cable not seated or damaged." },
        { "cause": "Software/firmware", "percent": 10, "description": "Try network settings reset, then DFU restore." }
      ],
      "repair_steps": [
        "1. Reset network settings",
        "2. DFU restore",
        "3. Check antenna connections",
        "4. If persists: WiFi IC replacement (micro-soldering)"
      ],
      "test_procedure": [
        "WiFi: connect to 2.4GHz and 5GHz networks, speed test",
        "Bluetooth: pair AirPods or speaker",
        "AirDrop: test file transfer",
        "Check Settings > General > About > WiFi Address (if 'N/A' = chip dead)"
      ],
      "models_affected": ["*"],
      "related_patterns": []
    },
    {
      "id": "sep_panic",
      "keywords": ["SEP panic", "SEP Panic", "Secure Enclave"],
      "category": "kernelPanic",
      "component": "secure_enclave",
      "severity": "critical",
      "confidence": 95,
      "title": "Secure Enclave Processor panic",
      "diagnosis": "The SEP crashed. This is a critical, board-level issue.",
      "probabilities": [
        { "cause": "SEP hardware failure", "percent": 90, "description": "SEP is part of the SoC. Not field-repairable." },
        { "cause": "Board damage near SEP", "percent": 10, "description": "Power rail issue affecting SEP." }
      ],
      "repair_steps": [
        "1. DFU restore (very unlikely to help but worth trying)",
        "2. Board swap — SEP is fused to SoC, cannot be replaced independently",
        "3. Device may be unrepairable if paired components are involved"
      ],
      "test_procedure": [
        "Face ID / Touch ID test",
        "Apple Pay enrollment test",
        "Keychain access test"
      ],
      "models_affected": ["*"],
      "related_patterns": []
    },
    {
      "id": "jetsam_memory_pressure",
      "keywords": ["JetsamEvent", "per-process-limit"],
      "category": "jetsam",
      "component": "system_memory",
      "severity": "informational",
      "confidence": 40,
      "title": "Memory pressure — app killed by Jetsam",
      "diagnosis": "iOS killed a process due to memory pressure. Usually normal behavior under heavy multitasking.",
      "probabilities": [
        { "cause": "Normal iOS behavior", "percent": 70, "description": "Heavy app usage, many background processes. Not a hardware issue." },
        { "cause": "Memory leak in app", "percent": 20, "description": "A specific app consuming excessive memory." },
        { "cause": "RAM defect", "percent": 10, "description": "If Jetsam events are extremely frequent (100+/day), may indicate bad RAM cells." }
      ],
      "repair_steps": [
        "1. Check frequency — occasional Jetsam is normal",
        "2. If excessive: identify the largest process in the log",
        "3. Force-close heavy apps, restart device",
        "4. If 100+ events/day: DFU restore, then suspect RAM if persists"
      ],
      "test_procedure": [
        "Monitor Jetsam frequency over 24h",
        "Note which apps trigger the most events",
        "Compare to baseline (5-20/day is normal under active use)"
      ],
      "models_affected": ["*"],
      "related_patterns": []
    }
  ]
}
```

### components.json

```json
{
  "components": {
    "lightning_flex": {
      "name": "Lightning / Charging Flex Cable",
      "aliases": ["charge port", "dock connector", "bottom flex"],
      "sensors_on_flex": ["mic1"],
      "parts_included": ["charging port", "bottom microphone", "haptic engine connector", "bottom screws bracket"],
      "difficulty": "easy",
      "estimated_time_minutes": 20,
      "ifixit_difficulty": 3
    },
    "display_touch": {
      "name": "Display Assembly",
      "aliases": ["screen", "LCD", "OLED", "digitizer"],
      "sensors_on_flex": ["als", "prox"],
      "difficulty": "easy",
      "estimated_time_minutes": 15,
      "ifixit_difficulty": 2
    },
    "soc_gpu": {
      "name": "System on Chip (GPU)",
      "aliases": ["A-series chip", "processor"],
      "difficulty": "not_repairable",
      "estimated_time_minutes": null,
      "note": "Part of SoC package. Board swap required."
    },
    "memory_nand": {
      "name": "RAM / NAND Storage",
      "aliases": ["memory", "flash", "storage"],
      "difficulty": "expert_microsolder",
      "estimated_time_minutes": 120,
      "note": "NAND can be swapped by expert. RAM is part of SoC (not repairable)."
    },
    "wifi_bt_chip": {
      "name": "WiFi / Bluetooth IC",
      "aliases": ["wireless chip", "USI module"],
      "difficulty": "expert_microsolder",
      "estimated_time_minutes": 90
    },
    "secure_enclave": {
      "name": "Secure Enclave Processor",
      "aliases": ["SEP", "biometric processor"],
      "difficulty": "not_repairable",
      "note": "Fused to SoC. Board swap required. Paired to device."
    },
    "thermal_system": {
      "name": "Thermal Monitoring System",
      "aliases": ["thermal sensor", "NTC"],
      "difficulty": "varies",
      "note": "Depends on which sensor. Usually on a flex cable."
    },
    "system_memory": {
      "name": "System Memory (RAM)",
      "difficulty": "not_repairable",
      "note": "Part of SoC package."
    }
  }
}
```

### Update Mechanism

```swift
class KnowledgeBaseManager: Observable {
    // 1. Load bundled JSON (always available)
    // 2. Check ~/Library/Application Support/iCrashDiag/knowledge/ for overrides
    // 3. On launch (if online): fetch version.json from GitHub raw
    //    - If remote version > local version: download updated files to app support dir
    //    - Show subtle "Knowledge base updated" banner
    // 4. Merge: local override > app support download > bundled
}
```

**GitHub URL pattern:** `https://raw.githubusercontent.com/{owner}/iCrashDiag/main/knowledge/{file}.json`

---

## UI Design

### Layout: 3-Column NavigationSplitView

```
+------------------+------------------------+--------------------------------+
|    SIDEBAR        |      CRASH LIST        |         DETAIL PANEL           |
|    (220pt)        |       (300pt)          |          (flexible)            |
+------------------+------------------------+--------------------------------+
| [Import Folder]  | [Search/Filter bar]    |  DIAGNOSIS                     |
| [Pull from USB]  |                        |  +---------------------------+ |
|                  | panic-full-2026-04-01   |  | [!] Hardware Issue — 95%  | |
| --- Categories   |  Kernel Panic  14:30   |  | mic1 sensor missing       | |
| All (369)        |  mic1 missing          |  | Lightning flex cable      | |
| Kernel Panic(261)|                        |  +---------------------------+ |
| Thermal (15)     | panic-full-2026-04-01   |                                |
| Jetsam (61)      |  Kernel Panic  14:31   |  PROBABILITIES                 |
| App Crash (12)   |  mic1 missing          |  85% — Nappe lightning         |
| GPU Event (1)    |                        |  10% — Codec IC                |
| OTA Update (27)  | panic-full-2026-04-02   |   5% — NTC resistor            |
| Watchdog (15)    |  Kernel Panic  09:15   |                                |
|                  |  mic1 missing          |  REPAIR STEPS                  |
| --- Severity     |                        |  1. Replace lightning flex...   |
| Critical (3)     | ...                    |  2. Test bottom mic...         |
| Hardware (276)   |                        |                                |
| Software (29)    |                        |  DEVICE INFO                   |
| Info (61)        |                        |  iPhone SE 2 (iPhone12,8)      |
|                  |                        |  iOS 18.3.1 (22D63)           |
| --- Device       |                        |  2026-04-01 14:30:22          |
| iPhone SE 2 (369)|                        |                                |
|                  |                        |  [Copy Report] [Export]        |
| --- Stats        |                        |  [Show Raw Panic String]       |
| 261 panics       |                        |                                |
| Apr 1 - Apr 9    |                        |  --- RAW DATA (collapsible) ---|
| 29 crashes/day   |                        |  panic(cpu 3 caller 0x...)     |
+------------------+------------------------+--------------------------------+
```

### Key Views

#### 1. Sidebar (`SidebarView`)
- **Import buttons** at top: "Import Folder" (always active) + "Pull from iPhone" (greyed out + tooltip if `idevicecrashreport` not found in PATH)
- **Category filters** with counts — click to filter list
- **Severity filters** with color dots (red=critical, orange=hardware, yellow=software, grey=info)
- **Device breakdown** if multiple devices detected
- **Quick stats** at bottom

#### 2. Crash List (`CrashListView`)
- Search bar: filter by filename, pattern, sensor, service
- Sort: by date (default), severity, category
- Each row shows: icon (color-coded severity), filename truncated, category badge, time, matched pattern summary
- Multi-select support for batch export

#### 3. Detail Panel (`CrashDetailView`)
- **Diagnosis card** (top): severity badge, confidence %, pattern name, component
- **Probabilities** bar chart: horizontal bars with percentages
- **Repair steps**: numbered list
- **Test procedure**: checklist
- **Device info**: model, iOS version, timestamp
- **Action buttons**: Copy Report (Markdown to clipboard), Export (file save dialog), Show Raw
- **Raw data** (collapsible): full panic string with syntax highlighting (regex-matched keywords highlighted)

#### 4. Overview / Report View (`OverviewView`)
When no crash is selected, or via toolbar button:
- **Summary card**: device, date range, total crashes, dominant diagnosis
- **Timeline chart**: crashes per day (SwiftUI Charts), color-coded by category
- **Pattern frequency**: horizontal bar chart of top patterns
- **Sensor frequency**: if applicable
- **Verdict**: hardware/software determination with confidence
- **Full report export**: single button exports complete analysis

#### 5. Toolbar
- **View mode toggle**: List / Timeline
- **Knowledge base status**: "v2026.04 — Up to date" or "Update available"
- **Device indicator**: when iPhone connected via USB, show device name + connection icon

### USB Flow

```
User clicks "Pull from iPhone"
  → Check: `which idevicecrashreport` in PATH
    → Not found: alert with install instructions (brew install libimobiledevice)
    → Found: 
      → Run `idevice_id -l` to list connected devices
        → No device: alert "No iPhone detected"
        → Device found:
          → Run `ideviceinfo -k DeviceName` + `ideviceinfo -k ProductType`
          → Show confirmation: "Pull crash logs from [iPhone name]?"
          → Run `idevicecrashreport -e /tmp/iCrashDiag-extract/`
          → Parse extracted .ips files
          → Show progress bar during extraction + parsing
```

---

## Parsing Engine

### Parser Architecture

```swift
protocol CrashParser {
    func canParse(bugType: Int, metadata: [String: Any]) -> Bool
    func parse(fileName: String, metadata: [String: Any], body: String) -> CrashLog?
}

// Concrete parsers
struct KernelPanicParser: CrashParser { ... }   // bug_type 210
struct JetsamParser: CrashParser { ... }         // bug_type 298
struct AppCrashParser: CrashParser { ... }       // bug_type 308, 309
struct GPUEventParser: CrashParser { ... }       // bug_type 284
struct OTAUpdateParser: CrashParser { ... }      // bug_type 183
struct ThermalEventParser: CrashParser { ... }   // bug_type 313
struct WatchdogParser: CrashParser { ... }       // bug_type 409

class CrashParserEngine {
    let parsers: [CrashParser]
    
    func parseFile(url: URL) async throws -> CrashLog {
        // 1. Read file
        // 2. Split: line 1 = metadata JSON, rest = body
        // 3. Parse metadata: extract bug_type
        // 4. Find matching parser
        // 5. Parse body
        // 6. Return CrashLog
    }
    
    func parseDirectory(url: URL) async throws -> [CrashLog] {
        // Concurrent parsing with TaskGroup
        // Progress callback for UI
    }
}
```

### .ips File Format Handling

**Line 1**: Always JSON metadata
```json
{"bug_type":"210","timestamp":"2026-04-01 14:30:22.00 +0200","os_version":"iPhone OS 18.3.1 (22D63)"}
```

**Rest of file**: Varies by bug_type
- **210 (panic)**: JSON with `product`, `panicString`, etc.
- **298 (Jetsam)**: JSON with `memoryStatus`, `memoryPages`, `processes[]`
- **308/309 (app crash)**: JSON with `exception`, `threads[]`, `usedImages[]`
- **284 (GPU)**: Small JSON with `analysis` object
- **183 (OTA)**: Plain text logs (NOT JSON)
- **313 (thermal)**: JSON with thermal metrics
- **409 (watchdog)**: JSON similar to panic

Parser must handle: malformed JSON, truncated files, non-UTF8 data, empty body.

---

## Diagnosis Engine

```swift
class DiagnosisEngine {
    let knowledgeBase: KnowledgeBase
    
    // Single crash diagnosis
    func diagnose(crash: CrashLog) -> Diagnosis? {
        // 1. Match panic string against known patterns (keyword search)
        // 2. If match: return pattern's diagnosis with confidence
        // 3. If multiple matches: return highest confidence
        // 4. If no match: return nil (unknown pattern)
    }
    
    // Multi-crash aggregate analysis
    func analyzeAll(crashes: [CrashLog]) -> AnalysisReport {
        // 1. Diagnose each crash individually
        // 2. Aggregate: count patterns, sensors, services
        // 3. Build timeline (crashes per day)
        // 4. Determine dominant diagnosis
        // 5. Compute overall verdict
        // 6. Cross-reference: if 95%+ crashes share same pattern → high confidence hardware
        // 7. Flag anomalies: if 1 crash type is different from others → mention separately
    }
}
```

### Confidence Scoring

- Base confidence from pattern definition (e.g., mic1_missing = 95%)
- Modifiers:
  - Same pattern repeated 10+ times → +5% (consistency bonus)
  - Same pattern on 50+ crashes → cap at pattern max (repetition doesn't add info)
  - Multiple different patterns → reduce each by 10% (mixed signals)
  - Single occurrence → -15% (could be transient)
  - Pattern matches specific model known to have this issue → +5%

---

## Export System

### Clipboard Export (Markdown)

```markdown
# iCrashDiag Report — iPhone SE (2nd gen)

## Summary
- **Device**: iPhone SE (2nd gen) (iPhone12,8)
- **iOS**: 18.3.1 (22D63)
- **Period**: April 1-9, 2026
- **Total crashes**: 369 (261 kernel panics, 61 Jetsam, 15 thermal, ...)
- **Verdict**: HARDWARE ISSUE — 95% confidence

## Primary Diagnosis
**Bottom microphone thermal sensor failure (mic1)**

261/261 kernel panics triggered by missing mic1 sensor on the lightning flex cable.

### Probabilities
- 85% — Lightning flex cable defective
- 10% — Audio codec IC damage
-  5% — NTC resistor failure

### Recommended Repair
1. Replace lightning/charging flex cable assembly
2. Test bottom microphone (Voice Memos record + playback)
3. Verify no new panic logs after 24h

## Timeline
| Date | Panics | Thermal | Jetsam | Other |
|------|--------|---------|--------|-------|
| Apr 1 | 34 | 2 | 8 | 4 |
| Apr 2 | 29 | 1 | 7 | 3 |
| ... |

## All Patterns Detected
| Pattern | Count | Severity | Component |
|---------|-------|----------|-----------|
| mic1_missing | 261 | Hardware | Lightning flex |
| jetsam_memory | 61 | Info | System memory |
| thermalmonitord | 15 | Hardware | Thermal system |

---
Generated by iCrashDiag v1.0 — https://github.com/{owner}/iCrashDiag
```

### File Export (JSON + Markdown)

Save dialog offers:
- `.md` — same as clipboard format
- `.json` — full structured data (all CrashLog objects + AnalysisReport + metadata)
- `.json + .md` — both files with same base name

JSON export includes raw data for external AI analysis tools.

---

## Project Structure

```
iCrashDiag/
├── iCrashDiag.xcodeproj
├── iCrashDiag/
│   ├── iCrashDiagApp.swift              # @main, app lifecycle
│   ├── ContentView.swift                 # NavigationSplitView shell
│   │
│   ├── Models/
│   │   ├── CrashLog.swift               # CrashLog, CrashCategory, StackFrame
│   │   ├── Diagnosis.swift              # Diagnosis, Severity, Probability, Verdict
│   │   ├── AnalysisReport.swift         # AnalysisReport, PatternFrequency
│   │   └── Session.swift                # Session cache model
│   │
│   ├── Parsing/
│   │   ├── CrashParserEngine.swift      # Main parser coordinator
│   │   ├── KernelPanicParser.swift
│   │   ├── JetsamParser.swift
│   │   ├── AppCrashParser.swift
│   │   ├── GPUEventParser.swift
│   │   ├── OTAUpdateParser.swift
│   │   ├── ThermalEventParser.swift
│   │   └── WatchdogParser.swift
│   │
│   ├── Diagnosis/
│   │   ├── DiagnosisEngine.swift        # Pattern matching + scoring
│   │   └── ConfidenceCalculator.swift   # Confidence modifiers
│   │
│   ├── Knowledge/
│   │   ├── KnowledgeBase.swift          # Load + merge JSON files
│   │   ├── KnowledgeBaseManager.swift   # Auto-update from GitHub
│   │   └── KnowledgeModels.swift        # Codable structs for JSON
│   │
│   ├── Services/
│   │   ├── USBDeviceService.swift       # libimobiledevice Process calls
│   │   ├── FileImportService.swift      # Folder import + .ips discovery
│   │   ├── ExportService.swift          # Markdown + JSON export
│   │   └── SessionCacheService.swift    # Save/load last session
│   │
│   ├── Views/
│   │   ├── Sidebar/
│   │   │   ├── SidebarView.swift        # Category filters, stats, import buttons
│   │   │   └── ImportButtonsView.swift
│   │   ├── CrashList/
│   │   │   ├── CrashListView.swift      # Searchable, sortable list
│   │   │   └── CrashRowView.swift       # Individual row
│   │   ├── Detail/
│   │   │   ├── CrashDetailView.swift    # Full diagnosis + raw data
│   │   │   ├── DiagnosisCardView.swift  # Severity badge, confidence
│   │   │   ├── ProbabilityBarsView.swift
│   │   │   └── RawPanicView.swift       # Syntax-highlighted raw text
│   │   ├── Overview/
│   │   │   ├── OverviewView.swift       # Aggregate report
│   │   │   └── TimelineChartView.swift  # SwiftUI Charts
│   │   └── Shared/
│   │       ├── SeverityBadge.swift
│   │       ├── CategoryBadge.swift
│   │       └── SearchBar.swift
│   │
│   ├── ViewModels/
│   │   └── AppViewModel.swift           # @Observable, central state
│   │
│   └── Resources/
│       └── knowledge/
│           ├── iphone-models.json
│           ├── panic-patterns.json
│           ├── crash-signatures.json
│           ├── components.json
│           └── version.json
│
├── knowledge/                            # Git-tracked, source of truth for auto-update
│   ├── iphone-models.json
│   ├── panic-patterns.json
│   ├── crash-signatures.json
│   ├── components.json
│   └── version.json
│
├── README.md
├── LICENSE                               # MIT
└── .github/
    └── workflows/
        └── build.yml                     # CI: build + archive
```

---

## App State Management

```swift
@Observable
class AppViewModel {
    // State
    var crashLogs: [CrashLog] = []
    var selectedCrashID: UUID?
    var selectedCategory: CrashCategory?
    var selectedSeverity: Severity?
    var searchText: String = ""
    var sortOrder: SortOrder = .dateDescending
    var analysisReport: AnalysisReport?
    var isLoading: Bool = false
    var loadingProgress: Double = 0
    var loadingMessage: String = ""
    var connectedDevice: DeviceInfo?
    var knowledgeBaseVersion: String = ""
    
    // Computed
    var filteredCrashLogs: [CrashLog] { ... }
    var selectedCrash: CrashLog? { ... }
    var categoryCounters: [CrashCategory: Int] { ... }
    var severityCounters: [Severity: Int] { ... }
    
    // Services
    let parserEngine: CrashParserEngine
    let diagnosisEngine: DiagnosisEngine
    let knowledgeBase: KnowledgeBase
    let usbService: USBDeviceService
    let exportService: ExportService
    
    // Actions
    func importFolder(url: URL) async { ... }
    func pullFromUSB() async { ... }
    func exportReport(format: ExportFormat) { ... }
    func copyReportToClipboard() { ... }
}
```

---

## Edge Cases & Error Handling

| Scenario | Handling |
|----------|----------|
| Malformed .ips (not JSON) | Skip file, increment error counter, show in status bar |
| Empty .ips file | Skip silently |
| Unknown bug_type | Parse as "Unknown" category, show raw data only |
| No patterns match | Show "No known pattern detected" + raw data + suggest export for AI analysis |
| libimobiledevice not installed | USB button greyed out, tooltip: "Install with: brew install libimobiledevice" |
| No iPhone connected | Alert: "No iPhone detected. Connect via USB cable." |
| USB extraction fails | Show error from idevicecrashreport stderr |
| 10,000+ files | Parse concurrently with TaskGroup, show progress bar |
| GitHub knowledge update fails | Silently use bundled/cached version |
| Mixed devices in one folder | Show device breakdown in sidebar, filter by device |

---

## v1 Scope

**In scope:**
- Folder import + USB extraction
- Parse all .ips types (panic, thermal, Jetsam, app crash, GPU, OTA, watchdog)
- Pattern matching against knowledge base
- Confidence scores with probability breakdown
- Repair steps and test procedures
- Timeline chart (SwiftUI Charts)
- Export: clipboard Markdown + file (JSON/Markdown)
- Auto-updating JSON knowledge base
- Session cache (reopen last import)
- Multi-device support in same import

**Out of scope (future):**
- Real-time crash monitoring (watch for new crashes)
- Sysdiagnose (.tar.gz) parsing
- Symbolication of app crash stack traces
- Integration with repair management systems
- Community pattern submission (in-app)
- Localization (v1 is English, French comments OK)

---

## Verification Checklist

1. `xcodebuild` clean build with zero warnings
2. Import test folder (369 .ips files from iPhone SE 2) — all parsed
3. 261 kernel panics correctly diagnosed as mic1_missing
4. Sidebar filters work (category, severity)
5. Search filters crash list
6. Detail panel shows full diagnosis with probabilities
7. Overview shows timeline chart + verdict
8. Copy to clipboard produces valid Markdown
9. Export JSON is parseable and contains all crash data
10. USB pull works with connected iPhone (if libimobiledevice installed)
11. USB button greyed out when libimobiledevice not in PATH
12. Knowledge base loads from bundle
13. App launches without internet (offline mode)
