# Knowledge Base Expansion + Device Dashboard

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** (A) Expand panic-patterns.json from 40 to 150+ patterns by mining open-source iOS crash analysis projects and cross-referencing repair community knowledge; (B) Build a real-time device dashboard that shows the connected iPhone's screenshot as blurred background with live info cards.

**Architecture:**
- (A) Knowledge base: pure JSON expansion of `iCrashDiag/Resources/knowledge/panic-patterns.json`. Research sources: KSCrash, PLCrashReporter, XNU source, iFixit, Rossmann forums, Apple Developer docs, iOS forensics tools. New patterns cover EXC_* types, ARM64 signals, per-component hardware failures, jetsam reason codes, restore errors, GPU hang subtypes, watchdog subtypes, baseband crashes, SEP panics, PMU variants.
- (B) Dashboard: `DeviceDashboardView` shown from `WelcomeView` when device is connected. Fetches battery/storage/screenshot via libimobiledevice CLI tools. Screenshot blurred as background with glassmorphism info cards on top.

**Tech Stack:** Swift 6 / SwiftUI, `ideviceinfo`, `idevicescreenshot`, `idevice_id`, NSImage, JSON

---

## File Map

**Modified:**
- `iCrashDiag/Resources/knowledge/panic-patterns.json` — +110 new patterns (total 150+)
- `iCrashDiag/Services/USBDeviceService.swift` — add battery %, storage, screenshot capture
- `iCrashDiag/Models/CrashLog.swift` — extend DeviceInfo with batteryLevel, storageUsed, storageTotal
- `iCrashDiag/Views/WelcomeView.swift` — show DeviceDashboardView when device connected

**New:**
- `iCrashDiag/Views/Device/DeviceDashboardView.swift` — main dashboard view
- `iCrashDiag/Views/Device/DeviceScreenshotBackground.swift` — blurred screenshot background

---

### Task 1: Extend DeviceInfo + USBDeviceService

**Files:**
- Modify: `iCrashDiag/Services/USBDeviceService.swift`
- Modify: `iCrashDiag/Models/CrashLog.swift` (DeviceInfo struct, but it's actually in USBDeviceService)

- [ ] Extend `DeviceInfo` with optional fields:
```swift
struct DeviceInfo: Sendable {
    // existing fields ...
    let batteryLevel: Int?       // 0-100
    let storageUsed: Int64?      // bytes
    let storageTotal: Int64?     // bytes
    let screenshotPath: String?  // /tmp/icrashdiag_screenshot.png
}
```

- [ ] Add methods to `USBDeviceService`:
```swift
func batteryLevel(udid: String) -> Int? {
    let r = run(command: "ideviceinfo", arguments: ["-u", udid, "-k", "BatteryCurrentCapacity"])
    return r.exitCode == 0 ? Int(r.output.trimmingCharacters(in: .whitespacesAndNewlines)) : nil
}

func storageInfo(udid: String) -> (used: Int64, total: Int64)? {
    let totalR = run(command: "ideviceinfo", arguments: ["-u", udid, "-k", "TotalDiskCapacity"])
    let availR = run(command: "ideviceinfo", arguments: ["-u", udid, "-k", "TotalSystemAvailable"])
    guard totalR.exitCode == 0, let total = Int64(totalR.output.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
    let avail = Int64(availR.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    return (total - avail, total)
}

func captureScreenshot(udid: String) -> String? {
    let path = "/tmp/icrashdiag_screenshot_\(udid).png"
    let r = run(command: "idevicescreenshot", arguments: ["-u", udid, path])
    return r.exitCode == 0 ? path : nil
}
```

- [ ] Update `deviceInfo(udid:knowledgeBase:)` to call these and populate new fields

- [ ] Build: `swift build` — no errors

---

### Task 2: DeviceScreenshotBackground view

**Files:**
- Create: `iCrashDiag/Views/Device/DeviceScreenshotBackground.swift`

- [ ] Write the view:
```swift
import SwiftUI

struct DeviceScreenshotBackground: View {
    let screenshotPath: String?
    @State private var image: NSImage? = nil

    var body: some View {
        ZStack {
            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 40)
                    .saturation(0.6)
                    .brightness(-0.15)
                    .ignoresSafeArea()
                    .clipped()
            } else {
                // Fallback: dark gradient
                LinearGradient(
                    colors: [Color(red:0.05,green:0.07,blue:0.12), Color(red:0.10,green:0.12,blue:0.20)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
            // Overlay to ensure readability
            Color.black.opacity(0.35).ignoresSafeArea()
        }
        .onAppear { loadImage() }
        .onChange(of: screenshotPath) { loadImage() }
    }

    private func loadImage() {
        guard let path = screenshotPath else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let img = NSImage(contentsOfFile: path)
            DispatchQueue.main.async { self.image = img }
        }
    }
}
```

---

### Task 3: DeviceDashboardView

**Files:**
- Create: `iCrashDiag/Views/Device/DeviceDashboardView.swift`

- [ ] Write the full dashboard:
```swift
import SwiftUI

struct DeviceDashboardView: View {
    let device: DeviceInfo
    @Environment(AppViewModel.self) private var viewModel
    @State private var showFolderPicker = false
    @State private var isRefreshingScreenshot = false

    var body: some View {
        ZStack {
            DeviceScreenshotBackground(screenshotPath: device.screenshotPath)

            VStack(spacing: 24) {
                // Device header
                VStack(spacing: 6) {
                    Image(systemName: "iphone.gen3")
                        .font(.system(size: 48, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(device.name)
                        .font(.title2).fontWeight(.bold).foregroundStyle(.white)
                    HStack(spacing: 8) {
                        if let model = device.modelName {
                            Text(model).font(.subheadline).foregroundStyle(.white.opacity(0.7))
                        }
                        if let ios = device.osVersion {
                            Text("iOS \(ios)").font(.subheadline).foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }

                // Info cards row
                HStack(spacing: 12) {
                    if let bat = device.batteryLevel {
                        InfoCard(
                            icon: batteryIcon(bat),
                            value: "\(bat)%",
                            label: "Battery",
                            color: bat < 20 ? .red : bat < 50 ? .yellow : .green
                        )
                    }
                    if let used = device.storageUsed, let total = device.storageTotal {
                        let usedGB = String(format: "%.1f", Double(used) / 1e9)
                        let totalGB = String(format: "%.0f", Double(total) / 1e9)
                        InfoCard(icon: "internaldrive", value: "\(usedGB)/\(totalGB)GB", label: "Storage", color: .blue)
                    }
                    if let serial = device.serialNumber {
                        InfoCard(icon: "number", value: String(serial.prefix(8)), label: "Serial", color: .secondary)
                    }
                    if let build = device.buildVersion {
                        InfoCard(icon: "hammer", value: build, label: "Build", color: .secondary)
                    }
                }

                // Action buttons
                VStack(spacing: 10) {
                    Button {
                        Task { await viewModel.pullFromUSB() }
                    } label: {
                        Label("Pull Crash Logs from iPhone", systemImage: "arrow.down.circle.fill")
                            .frame(maxWidth: 280)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button { showFolderPicker = true } label: {
                        Label("Import Folder Instead…", systemImage: "folder.badge.plus")
                            .frame(maxWidth: 280)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .tint(.white.opacity(0.8))
                }
            }
            .padding(32)
        }
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                Task { await viewModel.importFolder(url: url); viewModel.startWatching(folder: url) }
            }
        }
    }

    private func batteryIcon(_ level: Int) -> String {
        switch level {
        case 0..<10: return "battery.0"
        case 10..<35: return "battery.25"
        case 35..<60: return "battery.50"
        case 60..<85: return "battery.75"
        default: return "battery.100"
        }
    }
}

private struct InfoCard: View {
    let icon: String
    let value: String
    let label: String
    var color: Color = .white

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.callout).fontWeight(.semibold).foregroundStyle(.white).monospacedDigit()
            Text(label)
                .font(.caption2).foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.15), lineWidth: 1))
    }
}
```

---

### Task 4: Wire into WelcomeView

**Files:**
- Modify: `iCrashDiag/Views/WelcomeView.swift`

- [ ] Replace the `if let device = viewModel.connectedDevice { DeviceCard }` block with:
```swift
if let device = viewModel.connectedDevice {
    DeviceDashboardView(device: device)
} else {
    // existing welcome content
}
```
Actually WelcomeView IS the detail pane — wrap the entire body:
```swift
var body: some View {
    if let device = viewModel.connectedDevice, viewModel.crashLogs.isEmpty {
        DeviceDashboardView(device: device)
    } else {
        // existing VStack content
    }
}
```

---

### Task 5: Knowledge base — 110+ new patterns

**Files:**
- Modify: `iCrashDiag/Resources/knowledge/panic-patterns.json`

Categories to add (see detailed patterns in implementation):
1. **App crash subtypes** (12 patterns): EXC_BAD_ACCESS KERN_INVALID_ADDRESS, EXC_BAD_ACCESS KERN_PROTECTION_FAILURE, SIGABRT assertion, SIGILL bad code signing, EXC_ARITHMETIC, EXC_BREAKPOINT Swift runtime, EXC_RESOURCE CPU, EXC_RESOURCE memory, EXC_GUARD file descriptor, 0x8badf00d app watchdog, OOM jetsam, Swift fatal error
2. **Kernel panic subtypes** (20 patterns): Double free, use-after-free, stack overflow, bus error alignment, undefined instruction, data abort specific strings (AppleNAND, H2FMI, WMR_PANIC), AMCC, DRAM calibration
3. **Jetsam subtypes** (10 patterns): per-reason codes (idle, vmcompressor, memory limit exceeded, per-process-limit, highwater), repeated jetsam specific processes
4. **Watchdog subtypes** (10 patterns): per-daemon (backboardd, mediaserverd, locationd, wifid, bluetoothd, nfcd, biometrickitd, fairplayd, trustd, accessoryd)
5. **GPU/Display** (8 patterns): AGX firmware panic, Metal shader OOM, display subsystem, HDCP failure, ProMotion refresh
6. **Baseband/Modem** (8 patterns): baseband crash types, modem firmware, SIM card panics, antenna issues
7. **SEP/Security** (6 patterns): SEP panic subtypes, Secure Boot failure, Touch ID/Face ID SEP communication
8. **PMU/Power** (8 patterns): PMIC variants, charging IC, battery authentication, sleep/wake specific
9. **Sensors/Peripherals** (10 patterns): accelerometer, gyroscope, magnetometer, barometer, ambient light (ALS), Touch IC (Azalea/Rumba/Meson), haptic motor, Face ID dot projector, lidar
10. **OTA/Update** (8 patterns): restore error codes (4013, 4014, 4015, 9, 14, 21, 4005), baseband update fail, SEP update fail

- [ ] Python script to merge new patterns into existing JSON:
```bash
python3 << 'EOF'
import json
with open('iCrashDiag/Resources/knowledge/panic-patterns.json') as f:
    data = json.load(f)
existing_ids = {p['id'] for p in data['patterns']}
new_patterns = [... all 110 patterns ...]
added = [p for p in new_patterns if p['id'] not in existing_ids]
data['patterns'].extend(added)
with open('iCrashDiag/Resources/knowledge/panic-patterns.json', 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
print(f"Added {len(added)} patterns, total: {len(data['patterns'])}")
EOF
```

---

### Task 6: Final commit

```bash
git add iCrashDiag/Resources/knowledge/panic-patterns.json \
        iCrashDiag/Services/USBDeviceService.swift \
        iCrashDiag/Views/Device/ \
        iCrashDiag/Views/WelcomeView.swift
git commit -m "feat: 150+ pattern knowledge base + connected device dashboard"
git push origin main
```
