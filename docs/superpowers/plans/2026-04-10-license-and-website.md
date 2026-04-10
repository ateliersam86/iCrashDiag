# iCrashDiag — License Backend + Website Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ship a Cloudflare Worker license backend, integrate server-validated licensing into the macOS app (50-file freemium gate, Keychain storage, grace period), and deploy a landing page website.

**Architecture:** Three subsystems — (A) Cloudflare Worker with KV storage handles activation/validation/revocation; (B) Swift LicenseService validates on launch, stores key in macOS Keychain, and enforces a 50-file gate; (C) Static HTML landing page deployed to Cloudflare Pages via GitHub.

**Tech Stack:** Cloudflare Workers (TypeScript), Cloudflare KV, wrangler CLI, Swift 6 / SwiftPM, macOS Security framework, IOKit, HTML/CSS/Tailwind CDN.

---

## File Map

**New — Cloudflare Worker**
- `license-worker/wrangler.toml` — Worker config, KV binding, account
- `license-worker/package.json` — TypeScript dev deps
- `license-worker/tsconfig.json` — TS config
- `license-worker/src/index.ts` — Full Worker: /activate /validate /revoke

**New — Swift**
- `iCrashDiag/Services/LicenseService.swift` — Validation, Keychain, grace period, device ID
- `iCrashDiag/Views/License/LicenseGateView.swift` — Paywall overlay shown when free limit hit
- `iCrashDiag/Views/License/ActivateLicenseView.swift` — Sheet to enter + validate license key

**Modified — Swift**
- `iCrashDiag/Package.swift` — add IOKit linker setting
- `iCrashDiag/iCrashDiagApp.swift` — validate license on launch
- `iCrashDiag/ViewModels/AppViewModel.swift` — enforce 50-file gate in importFolder
- `iCrashDiag/Views/ContentView.swift` — wire LicenseGateView overlay

**New — Website**
- `website/index.html` — One-page landing (dark, professional)

---

### Task 1: Cloudflare Worker project files

**Files:** Create `license-worker/wrangler.toml`, `package.json`, `tsconfig.json`

- [ ] Write `license-worker/wrangler.toml`
- [ ] Write `license-worker/package.json`
- [ ] Write `license-worker/tsconfig.json`

---

### Task 2: Worker TypeScript source

**Files:** Create `license-worker/src/index.ts`

Full Worker with `/activate`, `/validate`, `/revoke` endpoints + CORS headers.

---

### Task 3: Deploy Worker + create KV namespace

- [ ] `cd license-worker && npm install`
- [ ] Create KV namespace via wrangler
- [ ] Update wrangler.toml with KV namespace ID
- [ ] Deploy Worker
- [ ] Set secrets: GUMROAD_SECRET, REVOKE_SECRET

---

### Task 4: Add IOKit to Package.swift

- [ ] Add `linkerSettings: [.linkedFramework("IOKit")]` to target
- [ ] `swift build` to verify

---

### Task 5: LicenseService.swift

Core service: IOPlatformUUID device ID, Keychain read/write, Worker validation call, grace period (7 days), state machine.

---

### Task 6: LicenseGateView + ActivateLicenseView

- `LicenseGateView` — full-screen overlay when free limit (50 files) reached
- `ActivateLicenseView` — sheet with text field + validate button

---

### Task 7: Wire license into app

- `iCrashDiagApp` — call `licenseService.validateOnLaunch()` in `onLaunch()`
- `AppViewModel` — cap `importFolder` at 50 files if `!licenseService.isPro`, set `showLicenseGate = true`
- `ContentView` — show `LicenseGateView` overlay when `viewModel.showLicenseGate`

---

### Task 8: Landing page

Single-file `website/index.html` with Tailwind CDN — dark theme, hero, features, pricing, download CTA.

---

### Task 9: Deploy landing page to Cloudflare Pages

Push `website/` to GitHub, connect to Cloudflare Pages as `icrashdiag.pages.dev`.

---

### Task 10: Make repo private + final commit

- `gh repo edit ateliersam86/iCrashDiag --visibility private`
- Commit all changes
- Push to main
