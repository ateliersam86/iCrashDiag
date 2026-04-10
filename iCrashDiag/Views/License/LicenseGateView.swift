import SwiftUI

struct LicenseGateView: View {
    @Environment(AppViewModel.self) private var viewModel
    @State private var showActivate = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.75)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 80, height: 80)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(spacing: 8) {
                    Text("Free Limit Reached")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("iCrashDiag Free supports up to 50 crash log files.\nUnlock unlimited analysis with a Pro license.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Feature list
                VStack(alignment: .leading, spacing: 10) {
                    ProFeatureRow(icon: "infinity", text: "Unlimited crash log files")
                    ProFeatureRow(icon: "sparkles", text: "Advanced AI pattern matching")
                    ProFeatureRow(icon: "arrow.down.circle.fill", text: "Future features & updates")
                    ProFeatureRow(icon: "iphone.gen3", text: "Unlimited USB device pulls")
                }
                .padding(.horizontal, 8)

                VStack(spacing: 10) {
                    Button {
                        showActivate = true
                    } label: {
                        Text("Enter License Key")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        if let url = URL(string: "https://icrashdiag.pages.dev/#pricing") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Text("Get a License — $9.99")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button("Continue with Free (50 files max)") {
                        viewModel.dismissLicenseGate()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                }
            }
            .padding(32)
            .frame(maxWidth: 400)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.4), radius: 30)
            )
        }
        .sheet(isPresented: $showActivate) {
            ActivateLicenseView()
        }
    }
}

private struct ProFeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
            Text(text)
                .font(.callout)
        }
    }
}
