import SwiftUI

struct SidebarView: View {
    @Environment(AppViewModel.self) private var viewModel
    @State private var showFolderPicker = false

    var body: some View {
        VStack(spacing: 0) {
            // Import actions — always visible at top
            VStack(spacing: 8) {
                Button {
                    showFolderPicker = true
                } label: {
                    Label("Import Folder…", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                Button {
                    Task { await viewModel.pullFromUSB() }
                } label: {
                    Label(
                        viewModel.usbAvailable ? "Pull from iPhone" : "Pull from iPhone",
                        systemImage: "iphone.gen3"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(!viewModel.usbAvailable)

                if !viewModel.usbAvailable {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("USB requires libimobiledevice:\nbrew install libimobiledevice")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 2)
                }

                // Connected device card
                if let device = viewModel.connectedDevice {
                    DeviceCard(device: device)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)

            Divider()

            if viewModel.crashLogs.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("No logs loaded")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else {
                List {
                    Section("Categories") {
                        FilterRow(
                            label: "All Crashes",
                            icon: "tray.full.fill",
                            count: viewModel.crashLogs.count,
                            isSelected: viewModel.selectedCategory == nil && viewModel.selectedSeverity == nil
                        ) {
                            viewModel.selectedCategory = nil
                            viewModel.selectedSeverity = nil
                        }

                        ForEach(viewModel.categoryCounters, id: \.0) { category, count in
                            FilterRow(
                                label: category.rawValue,
                                icon: category.systemImage,
                                count: count,
                                isSelected: viewModel.selectedCategory == category
                            ) {
                                viewModel.selectedCategory =
                                    viewModel.selectedCategory == category ? nil : category
                                viewModel.selectedSeverity = nil
                            }
                        }
                    }

                    Section("Severity") {
                        ForEach(viewModel.severityCounters, id: \.0) { severity, count in
                            Button {
                                viewModel.selectedSeverity =
                                    viewModel.selectedSeverity == severity ? nil : severity
                                viewModel.selectedCategory = nil
                            } label: {
                                HStack {
                                    SeverityBadge(severity: severity)
                                    Spacer()
                                    Text("\(count)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                            .buttonStyle(.plain)
                            .background(
                                viewModel.selectedSeverity == severity
                                    ? RoundedRectangle(cornerRadius: 5).fill(Color.accentColor.opacity(0.15))
                                    : nil
                            )
                        }
                    }

                    if let report = viewModel.analysisReport, !report.deviceModels.isEmpty {
                        Section("Devices") {
                            ForEach(
                                report.deviceModels.sorted(by: { $0.value > $1.value }),
                                id: \.key
                            ) { model, count in
                                HStack {
                                    Image(systemName: "iphone")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 14)
                                    Text(model)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(count)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                        }
                    }

                    if let report = viewModel.analysisReport {
                        Section("Stats") {
                            if let dr = report.dateRange {
                                let fmt: DateFormatter = {
                                    let f = DateFormatter()
                                    f.dateStyle = .short
                                    return f
                                }()
                                HStack {
                                    Text("Period")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(fmt.string(from: dr.start)) – \(fmt.string(from: dr.end))")
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                }
                                let days = max(1, Calendar.current.dateComponents(
                                    [.day], from: dr.start, to: dr.end
                                ).day ?? 1)
                                HStack {
                                    Text("Avg/day")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(report.totalCrashes / days)")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .frame(minWidth: 220)
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                Task { await viewModel.importFolder(url: url) }
            }
        }
        .onAppear {
            viewModel.checkUSBAvailability()
        }
    }
}

// MARK: - DeviceCard

private struct DeviceCard: View {
    let device: DeviceInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "iphone.gen3")
                    .font(.caption)
                    .foregroundStyle(.green)
                Text("Connected")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
                Spacer()
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
            }

            Divider()

            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                if let model = device.modelName {
                    Text(model)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let ios = device.osVersion {
                    HStack(spacing: 4) {
                        Text("iOS \(ios)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let build = device.buildVersion {
                            Text("(\(build))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                if let serial = device.serialNumber {
                    Text(serial)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospaced()
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.green.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.green.opacity(0.25), lineWidth: 1)
                )
        )
    }
}

// MARK: - FilterRow

private struct FilterRow: View {
    let label: String
    let icon: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 14)
                Text(label)
                    .font(.callout)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .primary : .primary)
                Spacer()
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .fontWeight(isSelected ? .semibold : .regular)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 1)
    }
}
