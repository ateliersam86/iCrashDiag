import SwiftUI
import UniformTypeIdentifiers

struct WelcomeView: View {
    @Environment(AppViewModel.self) private var viewModel
    @State private var showFolderPicker = false
    @State private var isDragOver = false

    var body: some View {
        Group {
        if let device = viewModel.connectedDevice, viewModel.crashLogs.isEmpty {
            DeviceDashboardView(device: device)
        } else {
        VStack(spacing: 32) {
            Spacer()

            // App icon + title
            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.11, green: 0.13, blue: 0.19),
                                         Color(red: 0.15, green: 0.18, blue: 0.28)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 96, height: 96)
                        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)

                    Image(systemName: "stethoscope")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.orange, Color(red: 1, green: 0.42, blue: 0.21)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                VStack(spacing: 4) {
                    Text("iCrashDiag")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("iPhone Crash Log Analyzer")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // What it does
            VStack(spacing: 12) {
                FeatureRow(
                    icon: "doc.text.magnifyingglass",
                    title: "Parse all .ips crash types",
                    subtitle: "Kernel panics, Jetsam, watchdogs, GPU events, OTA failures"
                )
                FeatureRow(
                    icon: "wrench.and.screwdriver",
                    title: "Hardware vs software diagnosis",
                    subtitle: "Confidence scores, repair steps, test procedures"
                )
                FeatureRow(
                    icon: "chart.bar.doc.horizontal",
                    title: "Timeline & export",
                    subtitle: "Full report as Markdown or JSON for further analysis"
                )
            }
            .padding(.horizontal, 40)

            // Connected device banner
            if let device = viewModel.connectedDevice {
                HStack(spacing: 10) {
                    Image(systemName: "iphone.gen3")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name)
                            .font(.callout)
                            .fontWeight(.semibold)
                        HStack(spacing: 4) {
                            if let model = device.modelName { Text(model) }
                            if let ios = device.osVersion { Text("• iOS \(ios)") }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Circle().fill(.green).frame(width: 8, height: 8)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.green.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.green.opacity(0.3), lineWidth: 1))
                )
                .padding(.horizontal, 40)
            }

            // Import actions
            VStack(spacing: 10) {
                Button {
                    showFolderPicker = true
                } label: {
                    Label("Import Crash Logs Folder…", systemImage: "folder.badge.plus")
                        .frame(width: 260)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("o", modifiers: .command)

                HStack(spacing: 8) {
                    Button {
                        Task { await viewModel.pullFromUSB() }
                    } label: {
                        Label("Pull from iPhone via USB", systemImage: "iphone.gen3")
                            .frame(width: 260)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(!viewModel.usbAvailable)
                }

                if !viewModel.usbAvailable {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.caption2)
                        Text("USB unavailable — install via: brew install libimobiledevice")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }

                Text("Tip: On your iPhone, go to Settings → Privacy → Analytics & Improvements → Analytics Data, then copy .ips files to a folder.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 60)
                    .padding(.top, 4)
            }

            Spacer()
        }
        .onAppear { viewModel.checkUSBAvailability() }
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in
                        if url.hasDirectoryPath {
                            await viewModel.importFolder(url: url)
                            viewModel.startWatching(folder: url)
                        } else if url.pathExtension.lowercased() == "ips" {
                            await viewModel.importSingleIPS(url: url)
                        }
                    }
                }
            }
            return true
        }
        .overlay(
            isDragOver ?
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8]))
                .background(Color.accentColor.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                .padding(12)
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.accentColor)
                        Text("Drop folder or .ips files")
                            .font(.headline)
                            .foregroundStyle(Color.accentColor)
                    }
                )
            : nil
        )
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
        } // else
        } // Group
    }
}

// MARK: - Feature Row

private struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 28)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
