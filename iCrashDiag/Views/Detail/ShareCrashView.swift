import SwiftUI
import AppKit

struct ShareCrashView: View {
    let crash: CrashLog
    @Environment(\.dismiss) private var dismiss

    @State private var selectedMode: ShareMode = .diagnosisOnly
    @State private var isLoading = false
    @State private var shareURL: String?
    @State private var errorMessage: String?
    @State private var didCopy = false

    var body: some View {
        VStack(spacing: 0) {

            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share Crash Report", bundle: .module)
                        .font(.headline)
                    Text(crash.fileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // Mode selector
                    Text("Choose what to share", bundle: .module)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.top, 4)

                    ForEach(ShareMode.allCases, id: \.self) { mode in
                        ShareModeCard(mode: mode, isSelected: selectedMode == mode) {
                            selectedMode = mode
                        }
                    }

                    // Privacy note
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Privacy", bundle: .module)
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text("Device name, app bundle IDs, and personal identifiers are never shared. Links expire after 30 days.", bundle: .module)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

                    // Result
                    if let url = shareURL {
                        VStack(spacing: 8) {
                            Text("Link created", bundle: .module)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                Text(url)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(url, forType: .string)
                                    didCopy = true
                                    Task { try? await Task.sleep(nanoseconds: 2_000_000_000); didCopy = false }
                                } label: {
                                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                                        .foregroundStyle(didCopy ? Color.green : Color.accentColor)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text("Copy link"))
                            }
                            .padding(8)
                            .background(Color(.textBackgroundColor).opacity(0.5),
                                        in: RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1)
                            )
                        }
                    }

                    if let err = errorMessage {
                        Label(err, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding()
            }

            Divider()

            // Footer actions
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Spacer()
                if shareURL == nil {
                    Button {
                        Task { await generateLink() }
                    } label: {
                        if isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Generate Link", systemImage: "link")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading)
                } else {
                    Button {
                        if let url = shareURL {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(url, forType: .string)
                            didCopy = true
                            Task {
                                try? await Task.sleep(nanoseconds: 2_000_000_000)
                                didCopy = false
                                dismiss()
                            }
                        }
                    } label: {
                        Label(didCopy ? "Copied!" : "Copy & Close", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(width: 400)
    }

    private func generateLink() async {
        isLoading = true
        errorMessage = nil
        do {
            let url = try await CommunityService.shared.createShareLink(crash: crash, mode: selectedMode)
            await MainActor.run { shareURL = url }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
        await MainActor.run { isLoading = false }
    }
}

// MARK: - Mode Card

private struct ShareModeCard: View {
    let mode: ShareMode
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: mode.icon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 24)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(mode.label)
                        .font(.callout)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(.primary)
                    Text(mode.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .padding(12)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.08)
                    : Color(.controlBackgroundColor).opacity(0.5),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
