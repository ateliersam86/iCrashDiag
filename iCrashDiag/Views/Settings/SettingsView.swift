import SwiftUI
import UserNotifications

struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var selectedTab = "general"

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag("general")

            NotificationsSettingsTab()
                .tabItem { Label("Notifications", systemImage: "bell") }
                .tag("notifications")

            KnowledgeBaseSettingsTab()
                .tabItem { Label("Knowledge Base", systemImage: "brain") }
                .tag("kb")

            ExportSettingsTab()
                .tabItem { Label("Export", systemImage: "square.and.arrow.up") }
                .tag("export")

            LicenseSettingsTab()
                .tabItem { Label("License", systemImage: "key.fill") }
                .tag("license")

            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag("about")
        }
        .frame(width: 480, height: 360)
        .preferredColorScheme(settings.colorScheme)
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $settings.appearanceMode) {
                    Text("System").tag("auto")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            } header: { Text("Appearance") }

            Section {
                Picker("Language", selection: $settings.languageCode) {
                    ForEach(AppSettings.languages, id: \.code) { lang in
                        Text("\(lang.flag)  \(lang.name)").tag(lang.code)
                    }
                }

                if settings.languageCode != "auto" {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text("Restart the app to fully apply the language change.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: { Text("Language") }

            Section {
                Toggle("Auto-detect iPhone via USB", isOn: $settings.usbPollingEnabled)
            } header: {
                Text("USB Detection")
            } footer: {
                Text("Polls for connected devices every 3 seconds.")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Notifications

private struct NotificationsSettingsTab: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("iPhone connected", isOn: $settings.notifyOnDeviceConnect)
                Toggle("Analysis complete", isOn: $settings.notifyOnAnalysisComplete)
            } header: { Text("System Notifications") }

            Section {
                Button("Request Notification Permission") {
                    requestPermission()
                }
            } header: { Text("Permissions") }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func requestPermission() {
        Task {
            try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        }
    }
}

// MARK: - Knowledge Base

private struct KnowledgeBaseSettingsTab: View {
    @State private var settings = AppSettings.shared
    @State private var isChecking = false
    @State private var updateStatus = ""
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        Form {
            Section {
                Toggle("Auto-update knowledge base on launch", isOn: $settings.autoUpdateKB)
                LabeledContent("Current version", value: viewModel.knowledgeBase.version)
            } header: { Text("Updates") }

            Section {
                HStack {
                    Button("Check for Updates Now") {
                        Task {
                            isChecking = true
                            updateStatus = "Checking…"
                            await KnowledgeBaseManager().checkAndUpdate()
                            updateStatus = "Done — restart to apply."
                            isChecking = false
                        }
                    }
                    .disabled(isChecking)

                    if isChecking { ProgressView().scaleEffect(0.7) }
                    if !updateStatus.isEmpty {
                        Text(updateStatus).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: { Text("Manual") }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Export

private struct ExportSettingsTab: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Include raw .ips body in JSON export", isOn: $settings.exportIncludeRawBody)
            } header: { Text("JSON Export") }

            Section {
                Text("Markdown and PDF exports always include the full diagnosis report.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - About

private struct LicenseSettingsTab: View {
    @State private var licenseService = LicenseService.shared
    @State private var showActivate = false

    var body: some View {
        VStack(spacing: 20) {
            // Status badge
            HStack(spacing: 10) {
                Image(systemName: licenseService.isPro ? "checkmark.seal.fill" : "lock.fill")
                    .font(.title2)
                    .foregroundStyle(licenseService.isPro ? Color.green : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(licenseService.isPro ? "iCrashDiag Pro" : "Free Version")
                        .font(.headline)
                    if licenseService.state == .graceExpired {
                        Text("Grace period expired — reconnect to validate")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if licenseService.isPro {
                        Text("Unlimited crash log analysis")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("50 crash log file limit")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding()
            .background(
                licenseService.isPro ? Color.green.opacity(0.08) : Color.secondary.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 10)
            )

            if licenseService.isPro, let key = licenseService.licenseKey {
                HStack {
                    Text("License key:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(key.prefix(8)) + "•••••••••••••")
                        .font(.system(.caption, design: .monospaced))
                    Spacer()
                }
            }

            Spacer()

            HStack {
                if licenseService.isPro {
                    Button("Deactivate License") {
                        licenseService.deactivate()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                } else {
                    Button("Enter License Key…") {
                        showActivate = true
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Get a License") {
                        NSWorkspace.shared.open(URL(string: "https://icrashdiag.pages.dev/#pricing")!)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showActivate) {
            ActivateLicenseView()
        }
    }
}

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(red: 0.09, green: 0.11, blue: 0.18))
                    .frame(width: 72, height: 72)
                    .shadow(radius: 4, y: 2)
                Image(systemName: "stethoscope")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(Color.orange)
            }

            VStack(spacing: 4) {
                Text("iCrashDiag").font(.title2).fontWeight(.bold)
                Text("Version 1.0").font(.caption).foregroundStyle(.secondary)
                Text("iPhone crash log analyzer for repair technicians")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 16) {
                Link("GitHub", destination: URL(string: "https://github.com/ateliersam86/iCrashDiag")!)
                    .font(.caption)
                Text("•").foregroundStyle(.tertiary)
                Text("MIT License").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
