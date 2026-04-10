import SwiftUI

struct DeviceDashboardView: View {
    let device: DeviceInfo
    @Environment(AppViewModel.self) private var viewModel
    @State private var showFolderPicker = false
    @State private var isPulling = false

    var body: some View {
        ZStack {
            DeviceScreenshotBackground(screenshotPath: device.screenshotPath)

            VStack(spacing: 28) {
                Spacer()

                // Device icon + name
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial.opacity(0.5))
                            .frame(width: 80, height: 80)
                        Image(systemName: "iphone.gen3")
                            .font(.system(size: 38, weight: .ultraLight))
                            .foregroundStyle(.white)
                    }
                    .overlay(
                        Circle()
                            .fill(.green)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().strokeBorder(.black.opacity(0.3), lineWidth: 2))
                            .offset(x: 28, y: 28)
                    )

                    VStack(spacing: 4) {
                        Text(device.name)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)

                        HStack(spacing: 6) {
                            if let model = device.modelName {
                                Text(model)
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                            if let ios = device.osVersion {
                                Text("·")
                                    .foregroundStyle(.white.opacity(0.4))
                                Text("iOS \(ios)")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                        }

                        HStack(spacing: 4) {
                            Circle().fill(.green).frame(width: 6, height: 6)
                            Text("Connected via USB")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .padding(.top, 2)
                    }
                }

                // Stats cards
                HStack(spacing: 10) {
                    if let bat = device.batteryLevel {
                        DeviceInfoCard(
                            icon: batteryIcon(bat),
                            value: "\(bat)%",
                            label: "Battery",
                            accentColor: bat < 20 ? .red : bat < 50 ? .yellow : .green
                        )
                    }

                    if let used = device.storageUsed, let total = device.storageTotal {
                        let usedGB = String(format: "%.1f", Double(used) / 1_000_000_000)
                        let totalGB = String(format: "%.0f", Double(total) / 1_000_000_000)
                        let pct = Double(used) / Double(total)
                        DeviceInfoCard(
                            icon: "internaldrive",
                            value: "\(usedGB) / \(totalGB)GB",
                            label: "Storage",
                            accentColor: pct > 0.9 ? .red : pct > 0.75 ? .orange : .blue
                        )
                    }

                    if let build = device.buildVersion {
                        DeviceInfoCard(
                            icon: "hammer.circle",
                            value: build,
                            label: "Build",
                            accentColor: .secondary
                        )
                    }

                    if let serial = device.serialNumber {
                        DeviceInfoCard(
                            icon: "number.circle",
                            value: String(serial.prefix(8)) + "…",
                            label: "Serial",
                            accentColor: .secondary
                        )
                    }
                }
                .padding(.horizontal, 16)

                // Actions
                VStack(spacing: 10) {
                    Button {
                        isPulling = true
                        Task {
                            await viewModel.pullFromUSB()
                            isPulling = false
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if isPulling {
                                ProgressView().controlSize(.small).tint(.white)
                            } else {
                                Image(systemName: "arrow.down.circle.fill")
                            }
                            Text(isPulling ? "Pulling crash logs…" : "Pull Crash Logs from iPhone")
                        }
                        .frame(maxWidth: 300)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isPulling)

                    Button {
                        showFolderPicker = true
                    } label: {
                        Label("Import from Folder Instead…", systemImage: "folder.badge.plus")
                            .frame(maxWidth: 300)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .tint(.white.opacity(0.85))
                }

                Spacer()

                // Crash count from history for this device
                if let session = viewModel.sessionHistory.first(where: {
                    $0.deviceName == device.name || $0.deviceModel == device.modelName
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                        Text("Last session: \(session.crashCount) crashes · \(session.severitySummary)")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.bottom, 8)
                }
            }
            .padding(.horizontal, 24)
        }
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                Task {
                    await viewModel.importFolder(url: url)
                    viewModel.startWatching(folder: url)
                }
            }
        }
    }

    private func batteryIcon(_ level: Int) -> String {
        switch level {
        case 0..<10:  return "battery.0percent"
        case 10..<35: return "battery.25percent"
        case 35..<60: return "battery.50percent"
        case 60..<85: return "battery.75percent"
        default:      return "battery.100percent"
        }
    }
}

// MARK: - Info Card

private struct DeviceInfoCard: View {
    let icon: String
    let value: String
    let label: String
    var accentColor: Color = .white

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(accentColor == .secondary ? .white.opacity(0.6) : accentColor)

            Text(value)
                .font(.system(.callout, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .background(.ultraThinMaterial.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
    }
}
