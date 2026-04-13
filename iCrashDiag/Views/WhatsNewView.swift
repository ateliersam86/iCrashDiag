import SwiftUI

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss

    private let entry = Changelog.current

    var body: some View {
        VStack(spacing: 0) {

            // Header
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(red: 0.09, green: 0.11, blue: 0.18))
                        .frame(width: 80, height: 80)
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
                    Image(systemName: "stethoscope")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(Color.orange)
                }
                Text("What's New in \(entry.version)", bundle: .module)
                    .font(.title2).fontWeight(.bold)
                Text(entry.date)
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.top, 32)
            .padding(.bottom, 24)

            // Feature list
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(entry.items.enumerated()), id: \.offset) { _, item in
                        ChangelogItemRow(item: item)
                    }
                }
                .padding(.horizontal, 32)
            }

            // Continue button
            Button("Continue") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return)
                .padding(.vertical, 24)
        }
        .frame(width: 460, height: 520)
    }
}
