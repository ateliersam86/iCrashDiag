# CLAUDE.md — iCrashDiag Agent Guide

> **This file is the single source of truth for any AI agent working on this project.**
> Read it entirely before touching any code. Every section is mandatory.

---

## 1. Project Overview

**iCrashDiag** is a native macOS app (SwiftUI, Swift 6, SwiftPM) that lets iPhone repair technicians import `.ips` crash log files, get an automated hardware/software diagnosis, and export repair reports.

- **Target**: macOS 14+ (Sonoma), Apple Silicon + Intel
- **Distribution**: Direct download (`.app` bundle), no App Store
- **Monetisation**: Freemium — first 50 logs free, Pro unlocks everything (Gumroad + Cloudflare Worker license backend)
- **Knowledge base**: offline JSON files bundled in the app, auto-updated from GitHub `main` branch

---

## 2. Architecture

```
iCrashDiag/
├── iCrashDiagApp.swift          # @main — language init, launch sequence, USB monitor
├── ContentView.swift            # Root navigation (NavigationSplitView + toolbar)
├── AppSettings.swift            # @Observable singleton — persisted via UserDefaults
│
├── Models/
│   ├── CrashLog.swift           # Parsed crash log struct
│   ├── Diagnosis.swift          # Diagnosis result struct
│   ├── AnalysisReport.swift     # Aggregated report (topPatterns, verdict…)
│   ├── AnalysisSession.swift    # Session history entry (var storedFolderPath!)
│   └── Changelog.swift         # ← SINGLE SOURCE OF TRUTH for release notes
│
├── Parsing/
│   └── CrashParserEngine.swift  # Parses .ips files into CrashLog
│
├── Diagnosis/
│   └── DiagnosisEngine.swift    # Matches CrashLog against KB patterns
│
├── Knowledge/
│   ├── KnowledgeBase.swift      # Loads JSON files (App Support first, then bundle)
│   └── KnowledgeBaseManager.swift # OTA update checker (fetches from GitHub main)
│
├── ViewModels/
│   └── AppViewModel.swift       # @Observable @MainActor — central state + actions
│
├── Services/
│   ├── SessionHistoryStore.swift # Persists last 50 sessions to App Support
│   ├── LicenseService.swift     # Keychain + Cloudflare Worker validation
│   ├── ExportService.swift      # Markdown / JSON export
│   ├── PDFExporter.swift        # PDF export
│   ├── NotificationService.swift
│   ├── USBDeviceService.swift   # libimobiledevice wrapper
│   └── LocalizationShim.swift   # Patches Bundle.main → Bundle.module for SwiftPM l10n
│
├── Views/                       # SwiftUI views (Settings/, Overview/, Detail/…)
└── Resources/
    ├── Info.plist               # ← VERSION IS HERE (CFBundleShortVersionString)
    ├── Localizable.strings (en/fr)
    └── knowledge/               # Bundled KB files (fallback if App Support empty)
```

**Key invariants:**
- `AppViewModel` is the only `@Observable @MainActor` state holder — never add global state elsewhere
- `KnowledgeBase`, `CrashParserEngine`, `DiagnosisEngine` are all `Sendable` — all three share the same `KnowledgeBase` instance; use `AppViewModel.reloadKnowledgeBase()` after a KB update
- `LocalizationShim.install()` **must** run before any bundle localization — it's the first call in `App.init()`
- Language: in "auto" mode, `AppleLanguages` key is **removed** from UserDefaults so `Bundle.module` follows the OS locale natively

---

## 3. Build & Deploy

### Quick dev loop
```bash
swift build                                   # compile
# then manually:
cp .build/debug/iCrashDiag iCrashDiag.app/Contents/MacOS/iCrashDiag
cp iCrashDiag/Resources/Info.plist iCrashDiag.app/Contents/Info.plist
codesign --force --deep --sign - iCrashDiag.app
open iCrashDiag.app
```

### Full rebuild (repackages the .app bundle from scratch)
```bash
bash make-app.sh          # debug
bash make-app.sh release  # optimised binary
```

### SourceKit false positives
SourceKit reports many "Cannot find X in scope" errors in this SwiftPM project — **ignore them entirely**. Only `swift build` output is authoritative. If `swift build` says `Build complete!` with no `error:` lines, the code is correct.

---

## 4. ⚠️ RELEASE PROCESS — MANDATORY

> Every time a feature is added or a significant bug is fixed, follow this checklist in order. No exceptions.

### Step 1 — Bump version (two files)

**`iCrashDiag/Resources/Info.plist`**
```xml
<key>CFBundleShortVersionString</key>
<string>X.Y.Z</string>          <!-- human version: 1.3.0 → 1.4.0 -->
<key>CFBundleVersion</key>
<string>N</string>              <!-- build number: increment by 1 -->
```

**`iCrashDiag/Models/Changelog.swift`**
Add a new `ChangelogEntry` at the **top** of `Changelog.entries`:
```swift
ChangelogEntry(version: "X.Y.Z", date: "Month YYYY", items: [
    ChangelogItem(icon: "sf.symbol.name", color: .orange, title: "Feature name", detail: "One-line description."),
    // … one item per significant change
]),
```
This drives both the "What's New" popup and the Settings → About → Release Notes changelog. Nothing else needs to change.

### Step 2 — Build & test
```bash
swift build                    # must be Build complete! with zero errors
bash make-app.sh               # repackage .app
open iCrashDiag.app
```
Verify:
- "What's New" popup appears with correct version + entries
- Settings → About shows "Version X.Y.Z" and the new entry at top of Release Notes
- Settings → Knowledge Base shows correct pattern count (no stale UI)

### Step 3 — Commit
```bash
git add -A
git commit -m "feat: vX.Y.Z — short summary"
```

### Step 4 — Tag
```bash
git tag -a vX.Y.Z HEAD -m "vX.Y.Z — short summary"
```

### Step 5 — Push (ask the user before this step)
```bash
git push origin main
git push origin --tags
```

### Step 6 — GitHub Release (ask the user before this step)
```bash
gh release create vX.Y.Z \
  --title "vX.Y.Z — short title" \
  --notes "$(cat <<'EOF'
## What's new
- Feature 1
- Feature 2

## Bug fixes
- Fix 1
EOF
)"
```

### Step 7 — Knowledge Base (only if patterns/models changed)
If `knowledge/panic-patterns.json`, `knowledge/iphone-models.json`, or `knowledge/components.json` changed:
```bash
# Bump knowledge/version.json date field
# e.g. "version": "2026.04.15"
git add knowledge/ && git commit -m "kb: bump to YYYY.MM.DD"
git push origin main   # users receive it automatically on next launch
```

---

## 5. Coding Conventions

- **No force-unwrap** (`!`) anywhere except in tests. Use `guard let`, `?? fallback`, or safe index access.
- **No `DispatchQueue.main.asyncAfter`** — use `Task { try? await Task.sleep(nanoseconds: …) }`.
- **`Task.detached`** for blocking I/O (e.g. `deviceInfo`). Capture all MainActor values before the detached block.
- **File writes** always use `options: .atomic` to prevent corruption on crash.
- **`@Observable` + `@MainActor`** for all ViewModels. No `@Published` / `ObservableObject`.
- **Localization**: wrap UI strings with `Text("…", bundle: .module)` or `NSLocalizedString("…", bundle: .main, comment: "")`. The `LocalizationShim` ensures `.main` resolves to `.module` strings.
- **Accessibility**: add `.accessibilityLabel` to all icon-only buttons and decorative badges.
- **No new global singletons** — use `@Environment` injection.

---

## 6. Known Architecture Decisions

| Decision | Reason |
|----------|--------|
| SwiftPM instead of Xcode project | Easier CI, git-friendly, no xcodeproj merge conflicts |
| `Bundle.module` for resources | SwiftPM puts resources in a separate bundle; `Bundle.main` misses them |
| `LocalizationShim` patching `Bundle.main` | SwiftUI `Text("…")` resolves via `Bundle.main`; shim redirects to `Bundle.module` |
| Session cache (`crashlogs.json` + `report.json`) | Large folders (500+ .ips files) take seconds to re-parse; cache makes re-open instant |
| License grace period in Keychain | UserDefaults is trivially editable; Keychain survives reinstall |
| KB update from `main` branch (not releases) | Allows hotfixing patterns without an app release |

---

## 7. What NOT To Do

- **Never** set `UserDefaults.standard.set([…], forKey: "AppleLanguages")` in "auto" mode — use `removeObject` instead
- **Never** call `UserDefaults.standard.synchronize()` — deprecated and causes performance issues
- **Never** use `NSApp.sendAction(Selector(("showSettingsWindow:")), …)` — use `@Environment(\.openSettings)` instead
- **Never** add `zh-Hant` or any language to `AppSettings.languages` without a corresponding `Localizable.strings` file
- **Never** commit `.wrangler/` state files, `build/*.dmg`, or `node_modules/` (already in `.gitignore`, verify before `git add -A`)
- **Never** push to `origin` or create a GitHub Release without asking the user first

---

## 8. Current Version State

| Field | Value |
|-------|-------|
| `CFBundleShortVersionString` | 1.3.0 |
| `CFBundleVersion` | 4 |
| Latest git tag | v1.3.0 |
| Knowledge base version | 2026.04.10 |
| Tags pushed to GitHub | ❌ not yet — ask user before pushing |
| GitHub Releases | ❌ none yet — ask user before creating |
