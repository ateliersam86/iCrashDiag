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
                Text("Allow access to get the most out of iCrashDiag")
                    .font(.title3).fontWeight(.bold)
                    .multilineTextAlignment(.center)
                Text("You can change these at any time in System Settings.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 32)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)

            // Permissions list
            VStack(spacing: 12) {
                PermissionRow(
                    icon: "bell.badge",
                    color: .orange,
                    title: "Notifications",
                    detail: "Alert you when a connected iPhone is detected and when analysis is complete.",
                    status: notifStatus,
                    isRequesting: isRequesting
                ) {
                    await requestNotifications()
                }
            }
            .padding(.horizontal, 28)

            Spacer()

            // Footer
            Button("Continue without permissions") { dismiss() }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 24)
        }
        .frame(width: 440, height: 380)
        .task { await refreshStatus() }
    }

    // MARK: -

    private func refreshStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notifStatus = settings.authorizationStatus
    }

    private func requestNotifications() async {
        isRequesting = true
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
        await refreshStatus()
        isRequesting = false
        settings.notificationPermissionAsked = true
    }
}

// MARK: - Permission row

private struct PermissionRow: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String
    let status: UNAuthorizationStatus
    let isRequesting: Bool
    let action: () async -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.semibold)
                Text(detail)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            statusButton
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var statusButton: some View {
        switch status {
        case .authorized:
            Label("Allowed", systemImage: "checkmark.circle.fill")
                .font(.caption).fontWeight(.medium)
                .foregroundStyle(.green)
                .labelStyle(.iconOnly)
                .font(.title3)
        case .denied:
            Button("Open Settings") {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        default:
            Button {
                Task { await action() }
            } label: {
                if isRequesting {
                    ProgressView().scaleEffect(0.7).frame(width: 50)
                } else {
                    Text("Allow")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isRequesting)
        }
    }
}
