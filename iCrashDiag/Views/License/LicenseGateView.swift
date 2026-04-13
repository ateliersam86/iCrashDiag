import SwiftUI

struct LicenseGateView: View {
    @Environment(AppViewModel.self) private var viewModel
    @State private var showActivate = false

    // MARK: - Gumroad URL
    // TODO: Replace with your real Gumroad product URL after creating it on gumroad.com
    private let gumroadURL = "https://ateliersam.gumroad.com/l/icrashdiag"

    var body: some View {
        ZStack {
            Color.black.opacity(0.75)
                .ignoresSafeArea()

            VStack(spacing: 0) {

                // Top — icon + headline
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 72, height: 72)
                        Image(systemName: "stethoscope")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.orange, Color(red: 1, green: 0.42, blue: 0.21)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }

                    VStack(spacing: 6) {
                        // Price anchor
                        HStack(spacing: 8) {
                            Text("$19.99", bundle: .module)
                                .font(.callout)
                                .strikethrough()
                                .foregroundStyle(.secondary)
                            Text("$9.99", bundle: .module)
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundStyle(.primary)
                            Text("launch price", bundle: .module)
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15), in: Capsule())
                        }
                        Text("One-time · your Mac · yours forever", bundle: .module)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 28)
                .padding(.bottom, 20)

                Divider().padding(.horizontal, 24)

                // Feature list — concrete and honest
                VStack(alignment: .leading, spacing: 11) {
                    GateFeatureRow(
                        icon: "infinity",
                        title: "Unlimited crash logs",
                        subtitle: "Analyze hundreds of logs at once — no cap",
                        color: .orange
                    )
                    GateFeatureRow(
                        icon: "doc.richtext",
                        title: "Export PDF & Markdown reports",
                        subtitle: "Send a clean report to your client or repair shop",
                        color: .orange
                    )
                    GateFeatureRow(
                        icon: "square.and.arrow.up",
                        title: "Crash share links",
                        subtitle: "Share a diagnosis URL in one click",
                        color: .orange
                    )
                    GateFeatureRow(
                        icon: "clock.arrow.circlepath",
                        title: "Full session history",
                        subtitle: "Access every past analysis, per device",
                        color: .orange
                    )
                    GateFeatureRow(
                        icon: "text.badge.checkmark",
                        title: "267-pattern offline knowledge base",
                        subtitle: "All diagnosis runs on your Mac — no cloud, no data sent",
                        color: .blue
                    )
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)

                Divider().padding(.horizontal, 24)

                // Actions
                VStack(spacing: 10) {
                    // Primary — buy
                    Button {
                        if let url = URL(string: gumroadURL) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "cart.fill")
                            Text("Get a License — $9.99", bundle: .module)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.orange)

                    // Money-back
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.shield")
                            .font(.caption2)
                        Text("30-day money-back guarantee. No questions asked.", bundle: .module)
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)

                    // Enter key
                    Button {
                        showActivate = true
                    } label: {
                        Text("Already have a license key? Activate →", bundle: .module)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                    // Dismiss
                    Button("Continue with Free (10 logs max)") {
                        viewModel.dismissLicenseGate()
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: 400)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.45), radius: 40)
            )
        }
        .sheet(isPresented: $showActivate) {
            ActivateLicenseView()
        }
    }
}

// MARK: - Feature Row

private struct GateFeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var color: Color = .orange

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 22, height: 22)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
