import SwiftUI
import UserNotifications

@main
struct iCrashDiagApp: App {
    init() {
        // Must run before any bundle localization is resolved
        LocalizationShim.install()

        let code = UserDefaults.standard.string(forKey: "languageCode") ?? "auto"
        if code != "auto" {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        } else {
            // "auto" = follow system. Remove any previously forced AppleLanguages so
            // Bundle.module falls back naturally to the OS locale (fr-FR, en-US, etc.).
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
    }

    @State private var viewModel = AppViewModel()
    @State private var settings = AppSettings.shared
    @State private var showWhatsNew = false
    @State private var showPermissions = false
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
                .sheet(isPresented: $showPermissions) {
                    PermissionOnboardingView()
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

        // Show in-app permission onboarding on first launch (never silently)
        if !settings.notificationPermissionAsked {
            let current = await UNUserNotificationCenter.current().notificationSettings()
            if current.authorizationStatus == .notDetermined {
                try? await Task.sleep(nanoseconds: 800_000_000) // let main window settle
                showPermissions = true
            } else {
                settings.notificationPermissionAsked = true
            }
        }

        // Knowledge base auto-update
        if settings.autoUpdateKB {
            let kbResult = await KnowledgeBaseManager().checkAndUpdate()
            if case .updated = kbResult {
                viewModel.reloadKnowledgeBase()
            }
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
                viewModel.usbAvailable = true
                let svc = viewModel.usbService
                let kb = viewModel.knowledgeBase
                let autoCap = settings.autoCaptureLogs
                Task.detached(priority: .userInitiated) { [self] in
                    let device = svc.deviceInfo(udid: udid, knowledgeBase: kb)
                    await MainActor.run {
                        self.viewModel.connectedDevice = device
                        if let d = device {
                            NotificationService.deviceConnected(name: d.name)
                            if autoCap {
                                Task { await self.viewModel.pullFromUSB() }
                            }
                        }
                    }
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
