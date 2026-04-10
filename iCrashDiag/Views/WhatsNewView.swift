import SwiftUI

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss

    private let changes: [(icon: String, color: Color, title: String, detail: String)] = [
        ("stethoscope",              .orange,  "iCrashDiag 1.0",         "Native macOS crash log analyzer for repair technicians."),
        ("doc.text.magnifyingglass", .blue,    "32 diagnostic patterns",  "Covers kernel panics, watchdogs, sensor failures, GPU, NAND, audio IC, Face ID, NFC, UWB, and more."),
        ("chart.bar.doc.horizontal", .purple,  "Progressive analysis",    "Crash logs appear in real-time as they're parsed. Hardware vs software verdict with confidence score."),
        ("iphone.gen3",              .green,   "USB extraction",          "Pull crash logs directly from a connected iPhone via libimobiledevice."),
        ("square.and.arrow.up",      .indigo,  "Export Markdown & JSON",  "Full diagnosis report for clipboard, file, or AI analysis tools."),
        ("arrow.clockwise.icloud",   .teal,    "Auto-updating KB",        "New iPhone models and patterns fetched from GitHub without an app update."),
    ]

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
                Text("What's New in iCrashDiag")
                    .font(.title2).fontWeight(.bold)
            }
            .padding(.top, 32)
            .padding(.bottom, 24)

            // Feature list
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(changes.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(item.color.opacity(0.15))
                                    .frame(width: 40, height: 40)
                                Image(systemName: item.icon)
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(item.color)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .fontWeight(.semibold)
                                Text(item.detail)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
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
