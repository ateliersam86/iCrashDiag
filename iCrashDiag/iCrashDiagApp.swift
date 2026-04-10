import SwiftUI
import UserNotifications

@main
struct iCrashDiagApp: App {
    @State private var viewModel = AppViewModel()
    @State private var settings = AppSettings.shared
    @State private var showWhatsNew = false
    @State private var usbMonitor = USBMonitor()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(viewModel)
                .preferredColorScheme(settings.colorScheme)
                .task { await onLaunch() }
                .sheet(isPresented: $showWhatsNew) {
                    WhatsNewView()
                }
                .onOpenURL { url in
                    guard url.pathExtension.lowercased() == "ips" else { return }
                    Task { await viewModel.importSingleIPS(url: url) }
                }
        }
        .defaultSize(width: 1260, height: 780)

        // Native Settings window (Cmd+,)
        Settings {
            SettingsView()
                .environment(viewModel)
        }
    }

    // MARK: - Launch sequence

    private func onLaunch() async {
        // Validate license in background
        await viewModel.licenseService.validateOnLaunch()

        // Apply language override (takes effect on next launch)
        if settings.languageCode != "auto" {
            UserDefaults.standard.set([settings.languageCode], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }

        // Request notification permission silently
        try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])

        // Knowledge base auto-update
        if settings.autoUpdateKB {
            await KnowledgeBaseManager().checkAndUpdate()
        }

        // What's New
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        if settings.lastSeenVersion != appVersion {
            settings.lastSeenVersion = appVersion
            try? await Task.sleep(nanoseconds: 600_000_000)
            showWhatsNew = true
        }

        // USB polling
        if viewModel.usbAvailable && settings.usbPollingEnabled {
            await startUSBMonitor()
        }
    }

    private func startUSBMonitor() async {
        await usbMonitor.start(interval: 3.0)
        await usbMonitor.setCallbacks(
            onConnected: { @MainActor [self] udid in
                let device = viewModel.usbService.deviceInfo(udid: udid, knowledgeBase: viewModel.knowledgeBase)
                viewModel.connectedDevice = device
                viewModel.usbAvailable = true
                if let d = device {
                    NotificationService.deviceConnected(name: d.name)
                }
            },
            onDisconnected: { @MainActor [self] _ in
                if viewModel.usbService.listDevices().isEmpty {
                    viewModel.connectedDevice = nil
                }
            }
        )
    }
}
