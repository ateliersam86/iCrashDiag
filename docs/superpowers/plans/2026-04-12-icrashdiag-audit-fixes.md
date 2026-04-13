# iCrashDiag — Audit Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Corriger les 40+ problèmes identifiés lors de l'audit complet de l'app iCrashDiag : sécurité licence, fonctionnalités cassées, performance, gestion d'erreurs, localisation, accessibilité et nettoyage SwiftUI.

**Architecture:** L'app est un package SwiftPM Swift 6 / SwiftUI macOS 14+. Elle suit une architecture ViewModel unique (`AppViewModel`) + services singletons. Les corrections sont organisées en 7 phases par priorité décroissante. Chaque phase est indépendante et peut être commitée séparément.

**Tech Stack:** Swift 6, SwiftUI, `@Observable`, Security framework (Keychain), UserNotifications, AppKit bridge, Swift Concurrency (async/await, AsyncStream, Task)

---

## Fichiers modifiés par phase

| Fichier | Phase(s) |
|---|---|
| `iCrashDiag/Services/LicenseService.swift` | 1 |
| `iCrashDiag/ViewModels/AppViewModel.swift` | 1, 2, 3, 4, 6 |
| `iCrashDiag/Views/Settings/SettingsView.swift` | 1 |
| `iCrashDiag/Services/ExportService.swift` | 2, 3 |
| `iCrashDiag/Services/NotificationService.swift` | 2, 6 |
| `iCrashDiag/Services/AppSettings.swift` | 2 |
| `iCrashDiag/Services/SessionHistoryStore.swift` | 2, 4 |
| `iCrashDiag/Knowledge/KnowledgeBaseManager.swift` | 4, 5 |
| `iCrashDiag/Views/Detail/ShareCrashView.swift` | 5 |
| `iCrashDiag/Views/Sidebar/SidebarView.swift` | 3, 5 |
| `iCrashDiag/Views/Overview/OverviewView.swift` | 3, 5 |
| `iCrashDiag/Models/CrashLog.swift` | 5 |
| `iCrashDiag/iCrashDiagApp.swift` | 5 |
| `iCrashDiag/Views/CrashList/CrashListView.swift` | 3, 7 |
| `iCrashDiag/Views/CrashList/CrashRowView.swift` | 7 |
| `iCrashDiag/Views/Shared/SeverityBadge.swift` | 7 |
| `iCrashDiag/Views/Shared/CategoryBadge.swift` | 7 |

---

## PHASE 1 — Sécurité (Critique)

### Task 1 : Corriger le bypass de licence (S1)

**Problème :** `AppViewModel.current` est un `static weak var` public. N'importe quel code peut appeler `AppViewModel.current?.unlockAllCrashes()` sans passer par la vérification de licence. `unlockAllCrashes()` n'a aucune guard.

**Fichiers :**
- Modify: `iCrashDiag/ViewModels/AppViewModel.swift:18,83-84,341-344`
- Modify: `iCrashDiag/Services/LicenseService.swift:82-84`

- [ ] **Step 1 : Supprimer `static weak var current` et passer par NotificationCenter dans AppViewModel**

Dans `AppViewModel.swift`, remplacer ligne 18 :
```swift
// AVANT
static weak var current: AppViewModel?
```
par rien (supprimer la ligne).

Puis dans `init()` (ligne 84-91), supprimer `AppViewModel.current = self` et ajouter un observer NotificationCenter :
```swift
init() {
    let kb = KnowledgeBase()
    self.knowledgeBase = kb
    self.parserEngine = CrashParserEngine(knowledgeBase: kb)
    self.diagnosisEngine = DiagnosisEngine(knowledgeBase: kb)
    self.sessionHistory = historyStore.load()
    // Observer pour l'activation licence
    NotificationCenter.default.addObserver(
        forName: .licenseActivated,
        object: nil,
        queue: .main
    ) { [weak self] _ in
        self?.unlockAllCrashes()
    }
}
```

- [ ] **Step 2 : Ajouter la guard dans `unlockAllCrashes()`**

Remplacer la méthode `unlockAllCrashes()` (ligne 341) :
```swift
func unlockAllCrashes() {
    guard licenseService.isPro else { return }
    lockedCrashIDs = []
    showLicenseGate = false
}
```

- [ ] **Step 3 : Ajouter l'extension Notification.Name et poster depuis LicenseService**

À la fin de `LicenseService.swift`, avant le dernier `}` du fichier, ajouter :
```swift
extension Notification.Name {
    static let licenseActivated = Notification.Name("iCrashDiag.licenseActivated")
}
```

Dans `LicenseService.activate()`, remplacer les lignes 80-84 :
```swift
// AVANT
state = .pro
await MainActor.run {
    AppViewModel.current?.unlockAllCrashes()
}
```
par :
```swift
state = .pro
NotificationCenter.default.post(name: .licenseActivated, object: nil)
```

- [ ] **Step 4 : Build pour vérifier qu'il n'y a plus de référence à `AppViewModel.current`**

```bash
cd /Users/samuelmuselet/Desktop/iCrashDiag
grep -r "AppViewModel.current" --include="*.swift" .
```
Attendu : aucun résultat.

- [ ] **Step 5 : Commit**
```bash
git add iCrashDiag/ViewModels/AppViewModel.swift iCrashDiag/Services/LicenseService.swift
git commit -m "fix(security): remove AppViewModel.current static ref, use NotificationCenter for license unlock"
```

---

### Task 2 : Déplacer `lastValidatedAt` vers le Keychain (S2)

**Problème :** La date de dernière validation est dans UserDefaults. L'utilisateur peut la supprimer pour avoir une grace period infinie.

**Fichier :** `iCrashDiag/Services/LicenseService.swift`

- [ ] **Step 1 : Ajouter la constante Keychain pour lastValidatedAt**

Dans `LicenseService`, après `private let keychainAccount = "licenseKey"` (ligne 27), ajouter :
```swift
private let keychainAccountTimestamp = "lastValidatedAt"
```

Et supprimer la ligne :
```swift
private let lastValidatedKey = "iCrashDiag.lastValidatedAt"
```

- [ ] **Step 2 : Remplacer les UserDefaults.standard.set(...) par des helpers Keychain**

Ajouter deux méthodes privées dans la section `// MARK: - Keychain` :
```swift
private func saveTimestamp(_ ts: Double) {
    let data = withUnsafeBytes(of: ts) { Data($0) }
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: keychainService,
        kSecAttrAccount as String: keychainAccountTimestamp,
    ]
    SecItemDelete(query as CFDictionary)
    let addQuery: [String: Any] = query.merging([
        kSecValueData as String: data,
        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
    ], uniquingKeysWith: { $1 })
    SecItemAdd(addQuery as CFDictionary, nil)
}

private func readTimestamp() -> Double {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: keychainService,
        kSecAttrAccount as String: keychainAccountTimestamp,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: AnyObject?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
          let data = result as? Data, data.count == 8
    else { return 0 }
    return data.withUnsafeBytes { $0.load(as: Double.self) }
}
```

- [ ] **Step 3 : Remplacer les 2 appels UserDefaults dans validateOnLaunch et activate**

Dans `validateOnLaunch()`, remplacer :
```swift
UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastValidatedKey)
```
par :
```swift
saveTimestamp(Date().timeIntervalSince1970)
```

Dans `activate(key:)`, idem (ligne 79).

- [ ] **Step 4 : Mettre à jour `isWithinGracePeriod()`**

Remplacer :
```swift
private func isWithinGracePeriod() -> Bool {
    let ts = UserDefaults.standard.double(forKey: lastValidatedKey)
    guard ts > 0 else { return false }
    let last = Date(timeIntervalSince1970: ts)
    let elapsed = Date().timeIntervalSince(last)
    return elapsed < gracePeriodDays * 86400
}
```
par :
```swift
private func isWithinGracePeriod() -> Bool {
    let ts = readTimestamp()
    guard ts > 0 else { return false }
    let elapsed = Date().timeIntervalSince(Date(timeIntervalSince1970: ts))
    return elapsed < gracePeriodDays * 86400
}
```

- [ ] **Step 5 : Vérifier qu'aucune référence à `lastValidatedKey` ne subsiste**
```bash
grep -n "lastValidatedKey\|lastValidatedAt.*UserDefaults" iCrashDiag/Services/LicenseService.swift
```
Attendu : aucun résultat.

- [ ] **Step 6 : Commit**
```bash
git add iCrashDiag/Services/LicenseService.swift
git commit -m "fix(security): move grace period timestamp from UserDefaults to Keychain"
```

---

### Task 3 : Améliorer le Keychain — accessibilité + erreur SecItemAdd (S3, S4)

**Fichier :** `iCrashDiag/Services/LicenseService.swift`

- [ ] **Step 1 : Changer `kSecAttrAccessibleAfterFirstUnlock` → `kSecAttrAccessibleWhenUnlocked`**

Dans `saveToKeychain(key:)`, remplacer ligne 181 :
```swift
kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
```
par :
```swift
kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
```

- [ ] **Step 2 : Vérifier le résultat de `SecItemAdd`**

Remplacer dans `saveToKeychain(key:)` :
```swift
SecItemAdd(addQuery as CFDictionary, nil)
```
par :
```swift
let status = SecItemAdd(addQuery as CFDictionary, nil)
if status != errSecSuccess {
    // Keychain write failed — log silently but don't lose the in-memory state
    print("[LicenseService] Keychain save failed: \(status)")
}
```

- [ ] **Step 3 : Commit**
```bash
git add iCrashDiag/Services/LicenseService.swift
git commit -m "fix(security): use kSecAttrAccessibleWhenUnlocked, check SecItemAdd status"
```

---

### Task 4 : Corriger les force-unwrap sur URLs externes (E1)

**Fichier :** `iCrashDiag/Views/Settings/SettingsView.swift`

- [ ] **Step 1 : Créer des constantes URL sûres en haut du fichier**

Après `import SwiftUI` dans `SettingsView.swift`, ajouter :
```swift
private let gumroadProductURL = URL(string: "https://ateliersam.gumroad.com/l/icrashdiag")
private let githubRepoURL = URL(string: "https://github.com/ateliersam86/iCrashDiag")
```

- [ ] **Step 2 : Remplacer le force-unwrap Gumroad dans `LicenseSettingsTab` (ligne 254)**

Remplacer :
```swift
Button("Get a License — $9.99") {
    NSWorkspace.shared.open(URL(string: "https://ateliersam.gumroad.com/l/icrashdiag")!)
}
```
par :
```swift
Button("Get a License — $9.99") {
    if let url = gumroadProductURL { NSWorkspace.shared.open(url) }
}
```

- [ ] **Step 3 : Remplacer le force-unwrap GitHub dans `AboutTab` (ligne 291)**

Remplacer :
```swift
Link("GitHub", destination: URL(string: "https://github.com/ateliersam86/iCrashDiag")!)
```
par :
```swift
if let url = githubRepoURL {
    Link("GitHub", destination: url)
}
```

- [ ] **Step 4 : Commit**
```bash
git add iCrashDiag/Views/Settings/SettingsView.swift
git commit -m "fix: remove force-unwrap on external URLs in SettingsView"
```

---

## PHASE 2 — Fonctionnalités cassées (Medium)

### Task 5 : Connecter `exportIncludeRawBody` à l'export JSON (F3)

**Problème :** Le toggle "Include raw .ips body" dans les Settings n'a aucun effet sur l'export JSON.

**Fichiers :**
- Modify: `iCrashDiag/Services/ExportService.swift:170-176`

- [ ] **Step 1 : Modifier `generateJSON` pour accepter un paramètre `includeRawBody`**

Remplacer la méthode `generateJSON` (ligne 170) :
```swift
func generateJSON(crashes: [CrashLog], report: AnalysisReport) throws -> Data {
    let export = ExportPayload(generatedAt: Date(), appVersion: "1.0", report: report, crashes: crashes)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(export)
}
```
par :
```swift
func generateJSON(crashes: [CrashLog], report: AnalysisReport, includeRawBody: Bool = true) throws -> Data {
    let exportedCrashes: [CrashLog]
    if includeRawBody {
        exportedCrashes = crashes
    } else {
        exportedCrashes = crashes.map { crash in
            var c = crash
            // rawBody et rawMetadata sont let — on passe par ExportableCrashLog
            return c
        }
    }
    let export = ExportPayload(generatedAt: Date(), appVersion: "1.0", report: report, crashes: exportedCrashes)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(export)
}
```

**Note :** `CrashLog` a `rawBody` et `rawMetadata` comme `let`. Pour vraiment les exclure proprement il faut un wrapper. Ajouter à la fin de `ExportService.swift`, avant le dernier `}` :

```swift
/// Wrapper Codable qui exclut rawBody selon la préférence utilisateur
private struct ExportPayloadNoRaw: Codable {
    let generatedAt: Date
    let appVersion: String
    let report: AnalysisReport
    let crashes: [CrashLogSlim]
}

private struct CrashLogSlim: Codable {
    // Tous les champs de CrashLog sauf rawBody
    let id: UUID
    let fileName: String
    let timestamp: Date
    let category: CrashCategory
    let osVersion: String?
    let deviceModel: String?
    let processName: String?
    let faultingService: String?
    let panicString: String?
    let missingSensors: [String]
    let diagnosis: Diagnosis?

    init(from crash: CrashLog) {
        self.id = crash.id
        self.fileName = crash.fileName
        self.timestamp = crash.timestamp
        self.category = crash.category
        self.osVersion = crash.osVersion
        self.deviceModel = crash.deviceModel
        self.processName = crash.processName
        self.faultingService = crash.faultingService
        self.panicString = crash.panicString
        self.missingSensors = crash.missingSensors
        self.diagnosis = crash.diagnosis
    }
}
```

Puis mettre à jour `generateJSON` :
```swift
func generateJSON(crashes: [CrashLog], report: AnalysisReport, includeRawBody: Bool = true) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    if includeRawBody {
        let export = ExportPayload(generatedAt: Date(), appVersion: "1.0", report: report, crashes: crashes)
        return try encoder.encode(export)
    } else {
        let slim = ExportPayloadNoRaw(
            generatedAt: Date(),
            appVersion: "1.0",
            report: report,
            crashes: crashes.map(CrashLogSlim.init)
        )
        return try encoder.encode(slim)
    }
}
```

- [ ] **Step 2 : Passer le paramètre depuis AppViewModel**

Dans `AppViewModel.swift`, trouver l'appel à `exportService.generateJSON` (méthode `exportJSON` ou similaire). Chercher :
```bash
grep -n "generateJSON" iCrashDiag/ViewModels/AppViewModel.swift
```

Dans le call site, passer le setting :
```swift
let data = try exportService.generateJSON(
    crashes: crashLogs,
    report: report,
    includeRawBody: AppSettings.shared.exportIncludeRawBody
)
```

- [ ] **Step 3 : Commit**
```bash
git add iCrashDiag/Services/ExportService.swift iCrashDiag/ViewModels/AppViewModel.swift
git commit -m "fix: wire exportIncludeRawBody setting to JSON export"
```

---

### Task 6 : Déclencher la notification "Analyse terminée" (F5)

**Problème :** `NotificationService.analysisComplete(count:verdict:)` existe mais n'est jamais appelée.

**Fichier :** `iCrashDiag/ViewModels/AppViewModel.swift`

- [ ] **Step 1 : Appeler la notification à la fin de `importFolder`**

Dans `importFolder`, juste avant `loadingStage = .done(count: crashLogs.count)` (autour de ligne 260), ajouter :
```swift
// Envoyer notification si activée
let verdict = analysisReport?.overallVerdict.isHardware == true ? "Hardware issue detected" : "No critical hardware issue found"
NotificationService.analysisComplete(count: crashLogs.count, verdict: verdict)
```

- [ ] **Step 2 : Commit**
```bash
git add iCrashDiag/ViewModels/AppViewModel.swift
git commit -m "fix: call NotificationService.analysisComplete after import finishes"
```

---

### Task 7 : Retirer zh-Hant du picker jusqu'à ce que le .lproj existe (F4)

**Problème :** La langue "繁體中文" apparaît dans le picker mais n'a pas de fichier de traduction. L'utilisateur la sélectionne et l'app reste en anglais sans explication.

**Fichier :** `iCrashDiag/Services/AppSettings.swift`

- [ ] **Step 1 : Supprimer zh-Hant de la liste**

Dans `AppSettings.languages`, supprimer la ligne :
```swift
("zh-Hant", "繁體中文",     "🇹🇼"),
```

- [ ] **Step 2 : Commit**
```bash
git add iCrashDiag/Services/AppSettings.swift
git commit -m "fix: remove zh-Hant from language picker (no .lproj bundle)"
```

---

### Task 8 : Corriger `updateSourcePath` — utiliser Codable au lieu de JSON brut (D1)

**Problème :** `SessionHistoryStore.updateSourcePath` modifie le JSON à la main via `JSONSerialization`. Fragile si les CodingKeys changent.

**Fichier :** `iCrashDiag/Services/SessionHistoryStore.swift`

- [ ] **Step 1 : Réécrire `updateSourcePath` avec le round-trip Codable**

Remplacer la méthode entière (lignes 47-56) :
```swift
func updateSourcePath(id: UUID, path: String) {
    var all = load()
    guard let idx = all.firstIndex(where: { $0.id == id }) else { return }
    all[idx] = all[idx].withSourceFolderPath(path)
    if let data = try? JSONEncoder().encode(all) {
        try? data.write(to: fileURL, options: .atomic)
    }
}
```

- [ ] **Step 2 : Ajouter `withSourceFolderPath` au modèle `AnalysisSession`**

Trouver le fichier `AnalysisSession.swift` :
```bash
find /Users/samuelmuselet/Desktop/iCrashDiag -name "AnalysisSession.swift"
```

Lire le modèle et ajouter une méthode `withSourceFolderPath` :
```swift
func withSourceFolderPath(_ path: String) -> AnalysisSession {
    AnalysisSession(
        id: id,
        date: date,
        sourceLabel: sourceLabel,
        deviceName: deviceName,
        deviceModel: deviceModel,
        iosVersion: iosVersion,
        crashes: crashes,
        storedFolderPath: storedFolderPath,
        sourceFolderPath: path
    )
}
```
**Note :** Adapter les paramètres selon les champs réels du modèle.

- [ ] **Step 3 : Commit**
```bash
git add iCrashDiag/Services/SessionHistoryStore.swift iCrashDiag/Models/AnalysisSession.swift
git commit -m "fix: rewrite updateSourcePath using Codable round-trip instead of raw JSON"
```

---

## PHASE 3 — Performance (Medium)

### Task 9 : Mettre en cache `filteredCrashLogs`, `categoryCounters`, `severityCounters` (P1-P3)

**Problème :** Ces 3 computed properties refiltrent tous les logs à chaque accès (6-8 fois par frame).

**Fichier :** `iCrashDiag/ViewModels/AppViewModel.swift`

- [ ] **Step 1 : Transformer filteredCrashLogs en stored property avec invalidation**

Dans `AppViewModel`, remplacer la computed property `filteredCrashLogs` (lignes 99-146) par :

D'abord ajouter les stored properties après `var showLicenseGate = false` :
```swift
private(set) var filteredCrashLogs: [CrashLog] = []
private(set) var categoryCounters: [(CrashCategory, Int)] = []
private(set) var severityCounters: [(Severity, Int)] = []
```

Puis créer la méthode de recalcul :
```swift
func rebuildDerivedData() {
    // filtered
    var logs = crashLogs
    switch quickFilter {
    case .all: break
    case .hardware: logs = logs.filter { $0.diagnosis?.severity == .hardware }
    case .critical: logs = logs.filter { $0.diagnosis?.severity == .critical }
    case .today:
        let start = Calendar.current.startOfDay(for: Date())
        logs = logs.filter { $0.timestamp >= start }
    case .reboots: logs = logs.filter(\.isRebootEvent)
    }
    if quickFilter == .all {
        if showRebootsOnly { logs = logs.filter(\.isRebootEvent) }
        if let cat = selectedCategory { logs = logs.filter { $0.category == cat } }
        if let sev = selectedSeverity { logs = logs.filter { $0.diagnosis?.severity == sev } }
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
    case .dateAscending:  logs.sort { $0.timestamp < $1.timestamp }
    case .severity:
        let order: [Severity] = [.critical, .hardware, .software, .informational]
        logs.sort { a, b in
            let ai = order.firstIndex(of: a.diagnosis?.severity ?? .informational) ?? 3
            let bi = order.firstIndex(of: b.diagnosis?.severity ?? .informational) ?? 3
            return ai < bi
        }
    case .category: logs.sort { $0.category.rawValue < $1.category.rawValue }
    case .confidence:
        logs.sort { ($0.diagnosis?.confidencePercent ?? 0) > ($1.diagnosis?.confidencePercent ?? 0) }
    }
    filteredCrashLogs = logs

    // counters
    var catCounts: [CrashCategory: Int] = [:]
    var sevCounts: [Severity: Int] = [:]
    for c in crashLogs {
        catCounts[c.category, default: 0] += 1
        sevCounts[c.diagnosis?.severity ?? .informational, default: 0] += 1
    }
    categoryCounters = CrashCategory.allCases.compactMap { cat in
        guard let count = catCounts[cat], count > 0 else { return nil }
        return (cat, count)
    }
    severityCounters = Severity.allCases.compactMap { sev in
        guard let count = sevCounts[sev], count > 0 else { return nil }
        return (sev, count)
    }
}
```

- [ ] **Step 2 : Supprimer les anciennes computed properties `categoryCounters` et `severityCounters`**

Supprimer les blocs `var categoryCounters: [(CrashCategory, Int)] { ... }` (lignes 152-159) et `var severityCounters: [(Severity, Int)] { ... }` (lignes 161-171).

- [ ] **Step 3 : Appeler `rebuildDerivedData()` aux bons endroits**

Chercher tous les `didSet` ou les endroits où `crashLogs`, `quickFilter`, `selectedCategory`, `selectedSeverity`, `showRebootsOnly`, `searchText`, `sortOrder` changent, et ajouter `rebuildDerivedData()` après.

Les 7 points d'invalidation :
- Dans `importFolder`, après `crashLogs.append(contentsOf: batch)` : `rebuildDerivedData()`
- Après `analysisReport = report` dans importFolder : `rebuildDerivedData()`
- Après tout setter de filtre dans la vue (utiliser `onChange` dans les vues concernées, ou faire des setters explicites dans le ViewModel)

Le plus propre sur les filtres — ajouter dans AppViewModel des méthodes setter qui appellent rebuild :
```swift
func setCategory(_ cat: CrashCategory?) {
    selectedCategory = cat
    rebuildDerivedData()
}
func setSeverity(_ sev: Severity?) {
    selectedSeverity = sev
    rebuildDerivedData()
}
func setSearchText(_ text: String) {
    searchText = text
    rebuildDerivedData()
}
func setSortOrder(_ order: SortOrder) {
    sortOrder = order
    rebuildDerivedData()
}
func setQuickFilter(_ filter: QuickFilter) {
    quickFilter = filter
    rebuildDerivedData()
}
```

Ou plus simplement, utiliser un `didSet` sur chaque propriété filtrante :
```swift
var searchText = "" { didSet { rebuildDerivedData() } }
var sortOrder: SortOrder = .dateDescending { didSet { rebuildDerivedData() } }
var selectedCategory: CrashCategory? { didSet { rebuildDerivedData() } }
var selectedSeverity: Severity? { didSet { rebuildDerivedData() } }
var showRebootsOnly: Bool = false { didSet { rebuildDerivedData() } }
var quickFilter: QuickFilter = .all { didSet { rebuildDerivedData() } }
```

- [ ] **Step 4 : Simplifier `countFor` dans `CrashListView`**

Dans `CrashListView.swift`, remplacer `countFor(_:)` (lignes 92-102) par une version qui utilise les données déjà calculées :
```swift
private func countFor(_ filter: QuickFilter) -> Int {
    switch filter {
    case .all: return viewModel.crashLogs.count
    case .hardware: return viewModel.crashLogs.filter { $0.diagnosis?.severity == .hardware }.count
    case .critical: return viewModel.crashLogs.filter { $0.diagnosis?.severity == .critical }.count
    case .today:
        let start = Calendar.current.startOfDay(for: Date())
        return viewModel.crashLogs.filter { $0.timestamp >= start }.count
    case .reboots: return viewModel.rebootCount
    }
}
```
**Note :** Ces compteurs de chips ne changent qu'avec l'import, pas avec les filtres actifs. Ils peuvent rester comme calculs rapides sur `crashLogs` non filtré — c'est correct et peu coûteux comparé au full filter/sort.

- [ ] **Step 5 : Build et vérifier**
```bash
cd /Users/samuelmuselet/Desktop/iCrashDiag
swift build 2>&1 | grep -E "error:|warning:" | head -30
```

- [ ] **Step 6 : Commit**
```bash
git add iCrashDiag/ViewModels/AppViewModel.swift iCrashDiag/Views/CrashList/CrashListView.swift
git commit -m "perf: cache filteredCrashLogs/categoryCounters/severityCounters, avoid recompute per render"
```

---

### Task 10 : DateFormatter statiques (B3, B7)

**Problème :** `DateFormatter()` est instancié dans le body SwiftUI (cher à chaque render).

**Fichiers :**
- `iCrashDiag/Views/Sidebar/SidebarView.swift:183`
- `iCrashDiag/Services/ExportService.swift:17`

- [ ] **Step 1 : SidebarView — extraire la DateFormatter en static**

Dans `SidebarView.swift`, dans le body de la section Stats (autour de ligne 183), remplacer le bloc :
```swift
let fmt: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .short
    return f
}()
```
par une référence à un formatter statique. Ajouter juste après `private struct SidebarView: View {` :
Chercher où est la struct qui contient ce code (c'est dans le body de la List, Section "Stats"). Placer la static en dehors de `body` dans la private struct concernée. Chercher la struct parente de cette section dans SidebarView.swift.

En pratique, l'ajouter en haut du fichier comme private constant :
```swift
private let statsDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .short
    return f
}()
```
Et remplacer l'utilisation inline par `statsDateFormatter`.

- [ ] **Step 2 : ExportService — même chose**

Dans `ExportService.swift`, déplacer la `DateFormatter` (ligne 17) hors de `generateMarkdown` :
```swift
// En propriété du struct ExportService
private static let exportDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    return f
}()
```
Et utiliser `Self.exportDateFormatter` dans `generateMarkdown`.

- [ ] **Step 3 : Commit**
```bash
git add iCrashDiag/Views/Sidebar/SidebarView.swift iCrashDiag/Services/ExportService.swift
git commit -m "perf: make DateFormatter static to avoid per-render allocation"
```

---

### Task 11 : Déplacer `USBDeviceService.deviceInfo` hors du main thread (P5)

**Fichier :** `iCrashDiag/iCrashDiagApp.swift:85`

- [ ] **Step 1 : Wrapper l'appel deviceInfo dans Task.detached**

Dans `iCrashDiagApp.startUSBMonitor()`, dans le callback `onConnected`, remplacer :
```swift
onConnected: { @MainActor [self] udid in
    let device = viewModel.usbService.deviceInfo(udid: udid, knowledgeBase: viewModel.knowledgeBase)
    viewModel.connectedDevice = device
    ...
```
par :
```swift
onConnected: { @MainActor [self] udid in
    Task {
        let device = await Task.detached(priority: .userInitiated) {
            viewModel.usbService.deviceInfo(udid: udid, knowledgeBase: viewModel.knowledgeBase)
        }.value
        await MainActor.run {
            viewModel.connectedDevice = device
            viewModel.usbAvailable = true
            if let d = device {
                NotificationService.deviceConnected(name: d.name)
                if settings.autoCaptureLogs {
                    Task { await viewModel.pullFromUSB() }
                }
            }
        }
    }
```

- [ ] **Step 2 : Build pour vérifier**
```bash
swift build 2>&1 | grep "error:" | head -20
```

- [ ] **Step 3 : Commit**
```bash
git add iCrashDiag/iCrashDiagApp.swift
git commit -m "perf: move USB deviceInfo calls to background task, unblock main thread"
```

---

## PHASE 4 — Gestion d'erreurs (Medium)

### Task 12 : Alertes sur les erreurs d'écriture export (E2)

**Problème :** Les exports (Markdown, JSON, PDF) swallowent les erreurs silencieusement.

**Fichier :** `iCrashDiag/ViewModels/AppViewModel.swift`

- [ ] **Step 1 : Chercher les `try?` sur les exports**
```bash
grep -n "try?" iCrashDiag/ViewModels/AppViewModel.swift | grep -i "write\|export"
```

- [ ] **Step 2 : Remplacer `try?` par `do/catch` avec errorMessage**

Pour chaque write silencieux dans les méthodes d'export, remplacer le pattern :
```swift
try? md.write(to: url, atomically: true, encoding: .utf8)
```
par :
```swift
do {
    try md.write(to: url, atomically: true, encoding: .utf8)
} catch {
    errorMessage = "Export failed: \(error.localizedDescription)"
}
```

Idem pour les writes JSON/Data.

- [ ] **Step 3 : Commit**
```bash
git add iCrashDiag/ViewModels/AppViewModel.swift
git commit -m "fix: show error alerts when export write fails instead of silently dropping"
```

---

### Task 13 : Écriture atomique pour les fichiers cache session (D4)

**Fichier :** `iCrashDiag/ViewModels/AppViewModel.swift:283,286` et `iCrashDiag/Services/SessionHistoryStore.swift:29,43`

- [ ] **Step 1 : Ajouter `.atomic` à tous les `Data.write` de cache**

Dans `AppViewModel.importFolder`, remplacer :
```swift
try? data.write(to: storageURL.appendingPathComponent("crashlogs.json"))
```
par :
```swift
try? data.write(to: storageURL.appendingPathComponent("crashlogs.json"), options: .atomic)
```

Idem pour `report.json` deux lignes plus bas.

Dans `SessionHistoryStore.save` et `delete` :
```swift
try? data.write(to: fileURL, options: .atomic)
```

- [ ] **Step 2 : Commit**
```bash
git add iCrashDiag/ViewModels/AppViewModel.swift iCrashDiag/Services/SessionHistoryStore.swift
git commit -m "fix: use atomic writes for session cache files to prevent corruption on force-quit"
```

---

### Task 14 : Feedback précis sur la mise à jour de la Knowledge Base (E6)

**Problème :** "Check for Updates" affiche "Done" même si le téléchargement a planté.

**Fichiers :**
- `iCrashDiag/Knowledge/KnowledgeBaseManager.swift`
- `iCrashDiag/Views/Settings/SettingsView.swift`

- [ ] **Step 1 : Faire retourner un statut détaillé depuis `checkAndUpdate`**

Dans `KnowledgeBaseManager.swift`, remplacer :
```swift
func checkAndUpdate() async {
    ...
    _ = await checkForUpdates(currentVersion: bundleVersion)
}
```
par :
```swift
enum UpdateResult {
    case updated, alreadyLatest, failed(String)
}

func checkAndUpdate() async -> UpdateResult {
    let bundleVersion: String
    if let url = Bundle.module.url(forResource: "version", withExtension: "json", subdirectory: "knowledge"),
       let data = try? Data(contentsOf: url),
       let file = try? JSONDecoder().decode(VersionFile.self, from: data) {
        bundleVersion = file.version
    } else { bundleVersion = "0" }

    do {
        let versionURL = remoteBaseURL.appendingPathComponent("version.json")
        let (data, _) = try await URLSession.shared.data(from: versionURL)
        let remote = try JSONDecoder().decode(VersionFile.self, from: data)
        if remote.version > bundleVersion {
            try await downloadAll()
            return .updated
        }
        return .alreadyLatest
    } catch {
        return .failed(error.localizedDescription)
    }
}
```

Et supprimer `checkForUpdates(currentVersion:)` (devenu inutile) ou garder pour compatibilité avec `iCrashDiagApp`.

**Note :** Dans `iCrashDiagApp.onLaunch`, l'appel `await KnowledgeBaseManager().checkAndUpdate()` doit être mis à jour pour ignorer le résultat (auto-update silencieux reste valide) :
```swift
_ = await KnowledgeBaseManager().checkAndUpdate()
```

- [ ] **Step 2 : Mettre à jour `KnowledgeBaseSettingsTab` pour afficher le bon statut**

Dans `SettingsView.swift`, dans le bouton "Check for Updates Now", remplacer :
```swift
Button("Check for Updates Now") {
    Task {
        isChecking = true
        updateStatus = "Checking…"
        await KnowledgeBaseManager().checkAndUpdate()
        updateStatus = "Done — restart to apply."
        isChecking = false
    }
}
```
par :
```swift
Button("Check for Updates Now") {
    Task {
        isChecking = true
        updateStatus = "Checking…"
        let result = await KnowledgeBaseManager().checkAndUpdate()
        switch result {
        case .updated:
            updateStatus = "Updated — restart to apply."
        case .alreadyLatest:
            updateStatus = "Already up to date."
        case .failed(let msg):
            updateStatus = "Failed: \(msg)"
        }
        isChecking = false
    }
}
```

- [ ] **Step 3 : Commit**
```bash
git add iCrashDiag/Knowledge/KnowledgeBaseManager.swift iCrashDiag/Views/Settings/SettingsView.swift
git commit -m "fix: KB update button shows accurate status (updated/latest/failed)"
```

---

## PHASE 5 — Nettoyage SwiftUI & Quick Fixes (Low)

### Task 15 : Remplacer `DispatchQueue.asyncAfter` par `Task.sleep` (B1)

**Fichier :** `iCrashDiag/Views/Detail/ShareCrashView.swift:90,143`

- [ ] **Step 1 : Remplacer le premier asyncAfter (ligne 90)**

```swift
// AVANT
DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
    didCopy = false
}
// APRÈS
Task {
    try? await Task.sleep(for: .seconds(2))
    didCopy = false
}
```

- [ ] **Step 2 : Remplacer le second asyncAfter (ligne 143)**

```swift
// AVANT
DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
    didCopy = false
    dismiss()
}
// APRÈS
Task {
    try? await Task.sleep(for: .seconds(2))
    didCopy = false
    dismiss()
}
```

- [ ] **Step 3 : Commit**
```bash
git add iCrashDiag/Views/Detail/ShareCrashView.swift
git commit -m "fix: replace DispatchQueue.asyncAfter with Task.sleep in ShareCrashView"
```

---

### Task 16 : Remplacer `.foregroundColor` par `.foregroundStyle` (B2)

**Fichier :** `iCrashDiag/Views/Detail/ShareCrashView.swift:95,184,200`

- [ ] **Step 1 : Chercher toutes les occurrences**
```bash
grep -n "foregroundColor" iCrashDiag/Views/Detail/ShareCrashView.swift
```

- [ ] **Step 2 : Remplacer chaque occurrence**
```bash
sed -i '' 's/\.foregroundColor(/.foregroundStyle(/g' iCrashDiag/Views/Detail/ShareCrashView.swift
```
**Attention :** Vérifier manuellement le résultat — `.foregroundColor` accepte `Color` directement, `.foregroundStyle` aussi, donc le changement est direct.

- [ ] **Step 3 : Chercher dans tous les autres fichiers**
```bash
grep -rn "foregroundColor" iCrashDiag/ --include="*.swift" | grep -v ".build"
```
Remplacer toutes les occurrences trouvées.

- [ ] **Step 4 : Commit**
```bash
git add -u
git commit -m "fix: replace deprecated .foregroundColor with .foregroundStyle across views"
```

---

### Task 17 : Corriger `SpreadWordBanner` — ne plus poller UserDefaults dans le body (B6)

**Fichier :** `iCrashDiag/Views/Overview/OverviewView.swift:302`

- [ ] **Step 1 : Utiliser `@AppStorage` à la place**

Remplacer dans `SpreadWordBanner` :
```swift
@State private var dismissed = false
private let dismissedKey = "iCrashDiag.spreadWordDismissed"

var body: some View {
    if !dismissed && !UserDefaults.standard.bool(forKey: dismissedKey) {
```
par :
```swift
@AppStorage("iCrashDiag.spreadWordDismissed") private var dismissed = false

var body: some View {
    if !dismissed {
```

Et remplacer le bouton dismiss :
```swift
Button {
    UserDefaults.standard.set(true, forKey: dismissedKey)
    dismissed = true
}
```
par :
```swift
Button {
    dismissed = true
}
```
(`@AppStorage` persiste automatiquement dans UserDefaults.)

- [ ] **Step 2 : Commit**
```bash
git add iCrashDiag/Views/Overview/OverviewView.swift
git commit -m "fix: use @AppStorage for SpreadWordBanner dismiss, remove UserDefaults polling in body"
```

---

### Task 18 : Corriger `isRebootEvent` insensible à la casse (F8)

**Fichier :** `iCrashDiag/Models/CrashLog.swift:154`

- [ ] **Step 1 : Remplacer les comparaisons case-sensitive**

Remplacer :
```swift
|| (category == .thermal && (panicString?.contains("thermal shutdown") == true
                              || panicString?.contains("Thermal shutdown") == true
                              || faultingService == "critical"))
```
par :
```swift
|| (category == .thermal && (
    panicString?.range(of: "thermal shutdown", options: .caseInsensitive) != nil
    || faultingService?.lowercased() == "critical"
))
```

- [ ] **Step 2 : Commit**
```bash
git add iCrashDiag/Models/CrashLog.swift
git commit -m "fix: isRebootEvent thermal check now case-insensitive"
```

---

### Task 19 : Corriger la comparaison de versions dans KnowledgeBaseManager (M2)

**Fichier :** `iCrashDiag/Knowledge/KnowledgeBaseManager.swift:31`

- [ ] **Step 1 : Remplacer la comparaison string par une comparaison numérique**

Ajouter un helper en bas du fichier, après le dernier `}` de l'actor :
```swift
private func isNewer(_ remote: String, than current: String) -> Bool {
    let parseVersion = { (v: String) -> [Int] in
        v.split(separator: ".").compactMap { Int($0) }
    }
    let r = parseVersion(remote)
    let c = parseVersion(current)
    let len = max(r.count, c.count)
    for i in 0..<len {
        let ri = i < r.count ? r[i] : 0
        let ci = i < c.count ? c[i] : 0
        if ri != ci { return ri > ci }
    }
    return false
}
```

Dans `checkForUpdates` (ou le nouveau `checkAndUpdate`), remplacer :
```swift
if remote.version > currentVersion {
```
par :
```swift
if isNewer(remote.version, than: currentVersion) {
```

- [ ] **Step 2 : Commit**
```bash
git add iCrashDiag/Knowledge/KnowledgeBaseManager.swift
git commit -m "fix: use numeric version comparison in KnowledgeBaseManager instead of lexicographic"
```

---

### Task 20 : Supprimer `UserDefaults.synchronize()` et `lastFlushIndex` (L4, F6)

**Fichiers :** `iCrashDiag/iCrashDiagApp.swift:13,20` et `iCrashDiag/ViewModels/AppViewModel.swift:195,225`

- [ ] **Step 1 : Supprimer les deux `UserDefaults.standard.synchronize()` dans iCrashDiagApp.swift**

Ligne 13 : supprimer `UserDefaults.standard.synchronize()`
Ligne 20 : supprimer `UserDefaults.standard.synchronize()`

- [ ] **Step 2 : Supprimer `lastFlushIndex` dans AppViewModel**

Ligne 195 : supprimer `var lastFlushIndex = 0`
Ligne 225 : supprimer `lastFlushIndex = index`

- [ ] **Step 3 : Commit**
```bash
git add iCrashDiag/iCrashDiagApp.swift iCrashDiag/ViewModels/AppViewModel.swift
git commit -m "chore: remove deprecated UserDefaults.synchronize() and dead lastFlushIndex variable"
```

---

### Task 21 : Mettre `StatCard` en `private` (ST2)

**Fichier :** `iCrashDiag/Views/Overview/OverviewView.swift:582`

- [ ] **Step 1 : Chercher et corriger**
```bash
grep -n "^struct StatCard" iCrashDiag/Views/Overview/OverviewView.swift
```
Remplacer `struct StatCard` par `private struct StatCard`.

- [ ] **Step 2 : Commit**
```bash
git add iCrashDiag/Views/Overview/OverviewView.swift
git commit -m "chore: make StatCard private, remove accidental public surface"
```

---

## PHASE 6 — Localisation (Medium)

### Task 22 : Localiser les strings hardcodées dans AppViewModel et NotificationService (L2, L3)

**Fichiers :**
- `iCrashDiag/ViewModels/AppViewModel.swift:69-76`
- `iCrashDiag/Services/NotificationService.swift:8-9`

- [ ] **Step 1 : Vérifier quelles clés existent déjà dans Localizable.strings**
```bash
find /Users/samuelmuselet/Desktop/iCrashDiag -name "Localizable.strings" | head -3
cat /Users/samuelmuselet/Desktop/iCrashDiag/iCrashDiag/Resources/en.lproj/Localizable.strings | grep -i "scanning\|building\|loaded\|iPhone Connected\|Analysis"
```

- [ ] **Step 2 : Mettre à jour `loadingMessage` dans AppViewModel**

Remplacer :
```swift
var loadingMessage: String {
    switch loadingStage {
    case .idle: return ""
    case .scanning: return "Scanning for .ips files…"
    case .parsing(let i, let t, _): return "\(i) / \(t)"
    case .analyzing: return "Building report…"
    case .done(let c): return "Loaded \(c) crash logs"
    }
}
```
par :
```swift
var loadingMessage: String {
    switch loadingStage {
    case .idle: return ""
    case .scanning:
        return NSLocalizedString("loading.scanning", bundle: .module, comment: "Scanning stage")
    case .parsing(let i, let t, _):
        return "\(i) / \(t)"
    case .analyzing:
        return NSLocalizedString("loading.analyzing", bundle: .module, comment: "Analyzing stage")
    case .done(let c):
        let fmt = NSLocalizedString("loading.done %lld", bundle: .module, comment: "Done, %lld = count")
        return String(format: fmt, c)
    }
}
```

- [ ] **Step 3 : Ajouter les clés manquantes dans chaque .strings**

Vérifier quels fichiers .strings existent et ajouter les clés `loading.scanning`, `loading.analyzing`, `loading.done %lld` dans chacun. Exemple pour `en.lproj/Localizable.strings` :
```
"loading.scanning" = "Scanning for .ips files…";
"loading.analyzing" = "Building report…";
"loading.done %lld" = "Loaded %lld crash logs";
```

- [ ] **Step 4 : Mettre à jour NotificationService**

Remplacer les strings hardcodées :
```swift
static func deviceConnected(name: String) {
    guard AppSettings.shared.notifyOnDeviceConnect else { return }
    send(
        title: NSLocalizedString("notification.device.connected.title", bundle: .module, comment: ""),
        body: String(format: NSLocalizedString("notification.device.connected.body %@", bundle: .module, comment: ""), name),
        id: "device-connected"
    )
}

static func analysisComplete(count: Int, verdict: String) {
    guard AppSettings.shared.notifyOnAnalysisComplete else { return }
    let titleFmt = NSLocalizedString("notification.analysis.title %lld", bundle: .module, comment: "")
    send(
        title: String(format: titleFmt, count),
        body: verdict,
        id: "analysis-complete"
    )
}
```

Ajouter dans chaque `.strings` :
```
"notification.device.connected.title" = "iPhone Connected";
"notification.device.connected.body %@" = "%@ is ready. Tap to pull crash logs.";
"notification.analysis.title %lld" = "Analysis Complete — %lld logs";
```

- [ ] **Step 5 : Build et vérifier**
```bash
swift build 2>&1 | grep "error:" | head -10
```

- [ ] **Step 6 : Commit**
```bash
git add iCrashDiag/ViewModels/AppViewModel.swift iCrashDiag/Services/NotificationService.swift
git add iCrashDiag/Resources/
git commit -m "fix(i18n): localize loadingMessage strings and NotificationService text"
```

---

## PHASE 7 — Accessibilité minimale (Critique pour App Store)

### Task 23 : Ajouter les annotations VoiceOver essentielles (A1)

**Objectif :** Pas un VoiceOver complet, mais les éléments critiques pour éviter un refus App Store.

**Fichiers :**
- `iCrashDiag/Views/CrashList/CrashListView.swift`
- `iCrashDiag/Views/CrashList/CrashRowView.swift`
- `iCrashDiag/Views/Shared/SeverityBadge.swift`
- `iCrashDiag/Views/Shared/CategoryBadge.swift`

- [ ] **Step 1 : `CrashRowView` — labelliser la barre de sévérité**

Dans `CrashRowView.swift`, trouver la `RoundedRectangle` colorée (barre de sévérité à gauche). Ajouter après le `.fill(...)` :
```swift
.accessibilityHidden(true) // Decorative, severity is read via the text label
```

- [ ] **Step 2 : `SeverityBadge` — ajouter un accessibilityLabel combiné**

Dans `SeverityBadge.swift`, sur le conteneur principal de la badge (HStack ou Label), ajouter :
```swift
.accessibilityLabel(Text("\(severity.rawValue) severity", bundle: .module))
.accessibilityElement(children: .ignore)
```

- [ ] **Step 3 : `CategoryBadge` — même chose**

Dans `CategoryBadge.swift`, sur le conteneur :
```swift
.accessibilityLabel(Text("\(category.rawValue) category", bundle: .module))
.accessibilityElement(children: .ignore)
```

- [ ] **Step 4 : SearchBar prompt en localisé**

Dans `CrashListView.swift`, remplacer :
```swift
.searchable(text: $vm.searchText, prompt: "Search crashes...")
```
par :
```swift
.searchable(text: $vm.searchText, prompt: Text("search.placeholder", bundle: .module))
```

Ajouter dans les `.strings` :
```
"search.placeholder" = "Search crashes...";
```

- [ ] **Step 5 : Boutons icon-only — ajouter des labels accessibilité**

Chercher les boutons sans texte dans tout le projet :
```bash
grep -rn "Image(systemName:" iCrashDiag/Views --include="*.swift" -l
```

Pour chaque bouton qui n'a qu'une image (xmark, doc.on.doc, etc.) ajouter `.accessibilityLabel(Text("action_name", bundle: .module))`.

Exemple dans `ShareCrashView.swift` pour le bouton close :
```swift
Button { dismiss() } label: {
    Image(systemName: "xmark.circle.fill")
}
.accessibilityLabel(Text("Close", bundle: .module))
```

- [ ] **Step 6 : Commit**
```bash
git add iCrashDiag/Views/
git commit -m "feat(a11y): add minimum VoiceOver annotations for App Store compliance"
```

---

## Vérification finale

Après toutes les phases :

- [ ] **Build complet sans erreur**
```bash
cd /Users/samuelmuselet/Desktop/iCrashDiag
swift build 2>&1 | grep -E "^.*error:" | head -20
```
Attendu : 0 erreur.

- [ ] **Vérifier qu'il n'y a plus de `static weak var current`**
```bash
grep -r "AppViewModel.current" --include="*.swift" .
```
Attendu : 0 résultat.

- [ ] **Vérifier qu'il n'y a plus de `foregroundColor(`**
```bash
grep -rn "\.foregroundColor(" iCrashDiag/ --include="*.swift"
```
Attendu : 0 résultat.

- [ ] **Vérifier qu'il n'y a plus de force-unwrap sur URL string**
```bash
grep -rn 'URL(string:.*".*")!' iCrashDiag/ --include="*.swift"
```
Attendu : 0 résultat.

- [ ] **Vérifier qu'il n'y a plus de `synchronize()`**
```bash
grep -rn "synchronize()" iCrashDiag/ --include="*.swift"
```
Attendu : 0 résultat.

---

## Récapitulatif des 23 tâches

| Task | Phase | Priorité | ID Audit |
|---|---|---|---|
| 1. License bypass fix | 1 Security | Critique | S1 |
| 2. Grace period → Keychain | 1 Security | Critique | S2 |
| 3. Keychain accessibility + SecItemAdd | 1 Security | Medium | S3, S4 |
| 4. Force-unwrap URLs | 1 Security | Critique | E1 |
| 5. exportIncludeRawBody wiring | 2 Features | Medium | F3 |
| 6. analysisComplete notification | 2 Features | Medium | F5 |
| 7. Remove zh-Hant | 2 Features | Medium | F4 |
| 8. updateSourcePath Codable | 2 Features | Medium | D1 |
| 9. Cache filteredCrashLogs | 3 Perf | Medium | P1, P2, P3 |
| 10. DateFormatter static | 3 Perf | Low | B3, B7 |
| 11. USB deviceInfo off main thread | 3 Perf | Medium | P5 |
| 12. Export error alerts | 4 Errors | Medium | E2 |
| 13. Atomic writes | 4 Errors | Medium | D4 |
| 14. KB update status feedback | 4 Errors | Medium | E6 |
| 15. Task.sleep au lieu de asyncAfter | 5 Cleanup | Low | B1 |
| 16. foregroundStyle | 5 Cleanup | Low | B2 |
| 17. @AppStorage SpreadWordBanner | 5 Cleanup | Low | B6 |
| 18. isRebootEvent case-insensitive | 5 Cleanup | Low | F8 |
| 19. Version comparison numérique | 5 Cleanup | Low | M2 |
| 20. Suppr. synchronize() + lastFlushIndex | 5 Cleanup | Low | L4, F6 |
| 21. StatCard private | 5 Cleanup | Low | ST2 |
| 22. Localisation loadingMessage + notifications | 6 i18n | Medium | L2, L3 |
| 23. Accessibilité VoiceOver minimal | 7 A11y | Critique | A1 |
