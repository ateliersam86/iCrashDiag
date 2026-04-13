import SwiftUI
import UserNotifications

/// Shown once after first launch to request permissions with context.
/// Never uses a system dialog without the user clicking a clear button first.
struct PermissionOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings = AppSettings.shared
    @State private var notifStatus: UNAuthorizationStatus = .notDetermined
    @State private var isRequesting = false

    var body: some View {
        VStack(spacing: 0) {

            // Header
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(red: 0.09, green: 0.11, blue: 0.18))
                        .frame(width: 72, height: 72)
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(Color.orange)
                }
                Text("Allow access to get the most out of iCrashDiag", bundle: .module)
                    .font(.title3).fontWeight(.bold)
                    .multilineTextAlignment(.center)
                Text("You can change these at any time in System Settings.", bundle: .module)
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 32)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)

            // Permissions list
            VStack(spacing: 12) {
                notificationRow
            }
            .padding(.horizontal, 28)

            Spacer()

            // Footer
            Button {
                settings.notificationPermissionAsked = true
                dismiss()
            } label: {
                Text("Continue without permissions", bundle: .module)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.bottom, 24)
        }
        .frame(width: 440, height: 380)
        .task { await refreshStatus() }
    }

    // MARK: - Notification row

    private var notificationRow: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "bell.badge")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Color.orange)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Notifications", bundle: .module).fontWeight(.semibold)
                Text("Alert you when a connected iPhone is detected and when analysis is complete.", bundle: .module)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            notifActionButton
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var notifActionButton: some View {
        switch notifStatus {
        case .authorized, .provisional:
            Label("Allowed", systemImage: "checkmark.circle.fill")
                .font(.callout).fontWeight(.medium)
                .foregroundStyle(.green)
                .labelStyle(.iconOnly)
                .font(.title3)

        case .denied:
            Button {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!
                )
                settings.notificationPermissionAsked = true
                dismiss()
            } label: {
                Text("Open Settings", bundle: .module)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

        default:
            Button {
                Task { @MainActor in await requestNotifications() }
            } label: {
                if isRequesting {
                    ProgressView().scaleEffect(0.7).frame(width: 50)
                } else {
                    Text("Allow", bundle: .module)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isRequesting)
        }
    }

    // MARK: -

    private func refreshStatus() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        notifStatus = s.authorizationStatus
    }

    private func requestNotifications() async {
        isRequesting = true
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await refreshStatus()
            isRequesting = false
            settings.notificationPermissionAsked = true

            if granted {
                // Brief pause to let user see the green checkmark, then auto-close
                try? await Task.sleep(nanoseconds: 800_000_000)
                dismiss()
            }
            // If not granted, sheet stays open showing "Open Settings" button
        } catch {
            // Request failed — open System Settings as fallback
            await refreshStatus()
            isRequesting = false
            settings.notificationPermissionAsked = true
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!
            )
            dismiss()
        }
    }
}
