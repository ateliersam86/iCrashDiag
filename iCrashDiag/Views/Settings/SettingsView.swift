import SwiftUI
import UserNotifications

private let gumroadProductURL = URL(string: "https://ateliersam.gumroad.com/l/icrashdiag")
private let githubRepoURL = URL(string: "https://github.com/ateliersam86/iCrashDiag")

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
        .frame(width: 520, height: 420)
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
                    Text("System", bundle: .module).tag("auto")
                    Text("Light", bundle: .module).tag("light")
                    Text("Dark", bundle: .module).tag("dark")
                }
                .pickerStyle(.segmented)
            } header: { Text("Appearance", bundle: .module) }

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
                        Text("Restart the app to fully apply the language change.", bundle: .module)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: { Text("Language", bundle: .module) }

            Section {
                Toggle("Auto-detect iPhone via USB", isOn: $settings.usbPollingEnabled)
                Toggle("Auto-capture logs on connect", isOn: $settings.autoCaptureLogs)
                    .disabled(!settings.usbPollingEnabled)
            } header: {
                Text("USB Detection", bundle: .module)
            } footer: {
                Text("When auto-capture is on, crash logs are pulled automatically each time an iPhone is connected and saved for later review.", bundle: .module)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Notifications

private struct NotificationsSettingsTab: View {
    @State private var settings = AppSettings.shared
    @State private var authStatus: UNAuthorizationStatus = .notDetermined
    @State private var showOnboarding = false

    var body: some View {
        Form {
            Section {
                Toggle("iPhone connected", isOn: $settings.notifyOnDeviceConnect)
                Toggle("Analysis complete", isOn: $settings.notifyOnAnalysisComplete)
            } header: { Text("Events", bundle: .module) }

            Section {
                HStack {
                    Text("System permission")
                    Spacer()
                    switch authStatus {
                    case .authorized:
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green).font(.callout)
                    case .denied:
                        Button("Open System Settings") {
                            NSWorkspace.shared.open(
                                URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!
                            )
                        }.buttonStyle(.bordered).controlSize(.small)
                    default:
                        Button("Allow Notifications…") { showOnboarding = true }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                    }
                }
            } header: { Text("Permissions", bundle: .module) }
             footer: { Text("Notifications are only sent when iCrashDiag is running.", bundle: .module) }
        }
        .formStyle(.grouped)
        .padding()
        .task { await refreshStatus() }
        .sheet(isPresented: $showOnboarding, onDismiss: { Task { await refreshStatus() } }) {
            PermissionOnboardingView()
        }
    }

    private func refreshStatus() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        authStatus = s.authorizationStatus
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
                LabeledContent("Current version", value: viewModel.knowledgeBase.version)
                LabeledContent("Patterns loaded", value: "\(viewModel.knowledgeBase.patterns.count)")
            } header: {
                Text("Knowledge Base", bundle: .module)
            } footer: {
                Text("The knowledge base is an offline database of crash signatures and repair patterns. It maps crash log identifiers to known hardware and software causes — no internet connection required for analysis. Keeping it up to date improves diagnosis accuracy.", bundle: .module)
            }

            Section {
                Toggle("Auto-update on launch", isOn: $settings.autoUpdateKB)
            } header: { Text("Updates", bundle: .module) }

            Section {
                HStack {
                    Button("Check for Updates Now") {
                        Task {
                            isChecking = true
                            updateStatus = "Checking…"
                            let result = await KnowledgeBaseManager().checkAndUpdate()
                            switch result {
                            case .updated(let v):
                                viewModel.reloadKnowledgeBase()
                                updateStatus = "Updated to v\(v) ✓"
                            case .alreadyUpToDate:
                                updateStatus = "Already up to date."
                            case .failed(let msg):
                                updateStatus = "Failed: \(msg)"
                            }
                            isChecking = false
                        }
                    }
                    .disabled(isChecking)

                    if isChecking { ProgressView().scaleEffect(0.7) }
                    if !updateStatus.isEmpty {
                        Text(updateStatus).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: { Text("Manual", bundle: .module) }
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
            } header: { Text("JSON Export", bundle: .module) }

            Section {
                Text("Markdown and PDF exports always include the full diagnosis report.", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - License

private struct LicenseSettingsTab: View {
    @State private var licenseService = LicenseService.shared
    @State private var showActivate = false

    private let features: [(icon: String, label: String, free: String, pro: String)] = [
        ("doc.text.magnifyingglass", "Crash log analysis",  "10 files max",   "Unlimited"),
        ("chart.bar.doc.horizontal","Analysis report",      "✓",              "✓"),
        ("timeline.selection",      "Timeline & charts",    "✓",              "✓"),
        ("arrow.clockwise.icloud",  "KB auto-updates",      "✓",              "✓"),
        ("doc.on.clipboard",        "Copy as Markdown",     "—",              "✓"),
        ("doc.text",                "Save Markdown file",   "—",              "✓"),
        ("doc.richtext",            "Export PDF",           "—",              "✓"),
        ("square.and.arrow.up",     "Export JSON",          "—",              "✓"),
        ("iphone.gen3",             "USB log extraction",   "—",              "✓"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {

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
                                .font(.caption).foregroundStyle(.orange)
                        } else if licenseService.isPro {
                            if let key = licenseService.licenseKey {
                                Text(String(key.prefix(8)) + "••••••••••••")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Analyse limited to \(AppViewModel.freeFileCap) crash log files")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(12)
                .background(
                    licenseService.isPro ? Color.green.opacity(0.08) : Color.secondary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 10)
                )

                // Comparison table
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("Feature").font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                        Spacer()
                        Text("Free").font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .center)
                        Text("Pro").font(.caption).fontWeight(.semibold).foregroundStyle(.orange)
                            .frame(width: 60, alignment: .center)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))

                    ForEach(Array(features.enumerated()), id: \.offset) { idx, row in
                        HStack(spacing: 8) {
                            Image(systemName: row.icon)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            Text(row.label).font(.callout)
                            Spacer()
                            Text(row.free)
                                .font(.caption)
                                .foregroundStyle(row.free == "—" ? Color.secondary.opacity(0.4) : Color.primary)
                                .frame(width: 80, alignment: .center)
                            Text(row.pro)
                                .font(.caption).fontWeight(.medium)
                                .foregroundStyle(licenseService.isPro ? Color.green : Color.orange)
                                .frame(width: 60, alignment: .center)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(idx % 2 == 0 ? Color.clear : Color.secondary.opacity(0.03))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15)))

                // CTA
                if !licenseService.isPro {
                    HStack(spacing: 10) {
                        Button("Enter License Key…") { showActivate = true }
                            .buttonStyle(.borderedProminent)
                        Button("Get Pro — $9.99") {
                            if let url = gumroadProductURL { NSWorkspace.shared.open(url) }
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    Button("Deactivate License") { licenseService.deactivate() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showActivate) {
            ActivateLicenseView()
        }
    }
}

private struct AboutTab: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                // App identity
                VStack(spacing: 16) {
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
                        Text("iCrashDiag", bundle: .module).font(.title2).fontWeight(.bold)
                        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("iPhone crash log analyzer for repair technicians", bundle: .module)
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    HStack(spacing: 16) {
                        if let url = githubRepoURL {
                            Link("GitHub", destination: url).font(.caption)
                        }
                        Text("•").foregroundStyle(.tertiary)
                        Text("MIT License", bundle: .module).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 24)
                .padding(.bottom, 20)

                Divider().padding(.horizontal, 24)

                // Changelog
                VStack(alignment: .leading, spacing: 0) {
                    Text("Release Notes", bundle: .module)
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 12)

                    ForEach(Changelog.entries, id: \.version) { entry in
                        ChangelogVersionSection(entry: entry)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ChangelogVersionSection: View {
    let entry: ChangelogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("v\(entry.version)")
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                Text(entry.date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)

            ForEach(Array(entry.items.enumerated()), id: \.offset) { _, item in
                ChangelogItemRow(item: item)
                    .padding(.horizontal, 24)
            }
        }
        .padding(.bottom, 16)
    }
}

// MARK: - Shared row (used in WhatsNewView too)

struct ChangelogItemRow: View {
    let item: ChangelogItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(item.color.opacity(0.15))
                    .frame(width: 34, height: 34)
                Image(systemName: item.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(item.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.callout).fontWeight(.semibold)
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
