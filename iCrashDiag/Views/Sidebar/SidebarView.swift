import SwiftUI

struct SidebarView: View {
    @Environment(AppViewModel.self) private var viewModel
    @State private var showFolderPicker = false

    var body: some View {
        List {
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

                if let report = viewModel.analysisReport {
                    Section("Stats") {
                        if let dr = report.dateRange {
                            let fmt: DateFormatter = {
                                let f = DateFormatter()
                                f.dateStyle = .short
                                return f
                            }()
                            LabeledContent("Period", value: "\(fmt.string(from: dr.start)) — \(fmt.string(from: dr.end))")
                                .font(.caption)
                        }
                        if let dr = report.dateRange, report.totalCrashes > 0 {
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
