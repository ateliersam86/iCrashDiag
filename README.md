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

## Screenshot

3-column layout: sidebar filters | crash list | diagnosis detail with probabilities, repair steps, and raw data viewer.

## Requirements

- macOS 14 (Sonoma) or later
- Optional: [libimobiledevice](https://libimobiledevice.org/) for USB extraction
  ```
  brew install libimobiledevice
  ```

## Build

Build and package as a proper `.app` bundle:

```bash
bash make-app.sh          # debug build → iCrashDiag.app
bash make-app.sh release  # release build
open iCrashDiag.app
```

Or run directly (command-line, no dock icon):
```bash
swift run
```

Or open in Xcode:
```bash
open Package.swift
```

## Knowledge Base

The knowledge base lives in `knowledge/` as JSON files. Contributions welcome:

- `iphone-models.json` — iPhone model identifiers to names, chips, sensors
- `panic-patterns.json` — crash patterns to diagnoses, repair steps
- `components.json` — hardware components with repair difficulty, time estimates

The app auto-checks for updates from this repo on launch.

## How It Works

1. **Import** .ips crash files from a folder or pull directly from a USB-connected iPhone
2. **Parse** each file — extract metadata (bug type, timestamp, OS version) and body (panic string, memory info, GPU events)
3. **Diagnose** by matching against known patterns in the knowledge base — each pattern has confidence scores and probability breakdowns
4. **Aggregate** all crashes into an analysis report with timeline, pattern frequency, and an overall hardware vs software verdict
5. **Export** the full report as Markdown (clipboard or file) or JSON for use with external AI analysis tools

## Supported Crash Types

| Bug Type | Category | Description |
|----------|----------|-------------|
| 210 | Kernel Panic | Full kernel panics with panic string |
| 409 | Watchdog | Service watchdog timeouts (thermalmonitord, backboardd, wifid) |
| 298 | Jetsam | Memory pressure events |
| 308/309 | App Crash | Application exceptions with stack traces |
| 284 | GPU Event | GPU firmware lockups |
| 183 | OTA Update | Software update failures |
| 313 | Thermal | Thermal/battery events |

## License

MIT License - see [LICENSE](LICENSE)
