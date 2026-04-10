import SwiftUI

struct OverviewView: View {
    let report: AnalysisReport
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Verdict banner
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: report.overallVerdict.isHardware ? "wrench.and.screwdriver.fill" : "checkmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(report.overallVerdict.isHardware ? .orange : .green)
                        VStack(alignment: .leading) {
                            Text(report.overallVerdict.isHardware ? "HARDWARE ISSUE DETECTED" : "NO HARDWARE ISSUE")
                                .font(.headline)
                            Text("\(report.overallVerdict.confidence)% confidence")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(report.overallVerdict.summary)
                        .font(.subheadline)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(report.overallVerdict.isHardware ? .orange.opacity(0.1) : .green.opacity(0.1))
                )

                if let diag = report.dominantDiagnosis {
                    DiagnosisCardView(diagnosis: diag)
                }

                // Reboot Events Dashboard
                let reboots = viewModel.rebootEvents
                if !reboots.isEmpty {
                    RebootDashboardCard(reboots: reboots)
                }

                // Hardware probability gauge
                HardwareGaugeView(report: report)

                HStack(spacing: 16) {
                    StatCard(title: "Total Crashes", value: "\(report.totalCrashes)", icon: "doc.text.fill")
                    StatCard(title: "Reboots", value: "\(viewModel.rebootCount)",
                             icon: "arrow.clockwise.circle.fill",
                             accent: viewModel.rebootCount > 0 ? .red : .secondary)
                    if let dr = report.dateRange {
                        let days = max(1, Calendar.current.dateComponents([.day], from: dr.start, to: dr.end).day ?? 1)
                        StatCard(title: "Per Day", value: "\(report.totalCrashes / days)", icon: "calendar")
                    }
                    StatCard(title: "Patterns", value: "\(report.topPatterns.count)", icon: "magnifyingglass")
                }

                if !report.crashesPerDay.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Timeline")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        TimelineChartView(crashesPerDay: report.crashesPerDay)
                    }
                }

                if !report.topPatterns.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Detected Patterns")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        ForEach(report.topPatterns) { pattern in
                            HStack {
                                SeverityBadge(severity: pattern.severity)
                                Text(pattern.title)
                                    .font(.caption)
                                Spacer()
                                Text("\(pattern.count)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .monospacedDigit()
                                Text(pattern.component)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                HStack {
                    Button("Copy Full Report") {
                        viewModel.copyReportToClipboard()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Export JSON...") {
                        exportJSON()
                    }
                    .buttonStyle(.bordered)

                    Button("Export Markdown...") {
                        exportMarkdown()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
    }

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "iCrashDiag-report.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let data = try? viewModel.exportService.generateJSON(crashes: viewModel.crashLogs, report: report) {
            try? data.write(to: url)
        }
    }

    private func exportMarkdown() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "iCrashDiag-report.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let md = viewModel.exportService.generateMarkdown(crashes: viewModel.crashLogs, report: report)
        try? md.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - Hardware Gauge

private struct HardwareGaugeView: View {
    let report: AnalysisReport
    @State private var animated = false

    private var hardwarePercent: Double {
        let total = report.totalCrashes
        guard total > 0 else { return 0 }
        let hw = report.topPatterns.filter { $0.severity == .hardware || $0.severity == .critical }
            .map(\.count).reduce(0, +)
        return min(1.0, Double(hw) / Double(total))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Hardware Risk")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(Int(hardwarePercent * 100))%")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(gaugeColor)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.12))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [.green, .yellow, .orange, .red],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .opacity(0.85)
                        )
                        .frame(width: animated ? geo.size.width * hardwarePercent : 0)
                        .animation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.3), value: animated)
                }
                .frame(height: 8)
            }
            .frame(height: 8)

            HStack {
                Text("Low risk").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("High risk").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        .onAppear { animated = true }
    }

    private var gaugeColor: Color {
        switch hardwarePercent {
        case 0..<0.3: return .green
        case 0.3..<0.6: return .yellow
        case 0.6..<0.8: return .orange
        default: return .red
        }
    }
}

// MARK: - Reboot Dashboard Card

private struct RebootDashboardCard: View {
    let reboots: [CrashLog]

    private var hardwareReboots: [CrashLog] {
        reboots.filter { $0.diagnosis?.severity == .hardware || $0.diagnosis?.severity == .critical }
    }
    private var softwareReboots: [CrashLog] {
        reboots.filter { $0.diagnosis?.severity == .software || $0.diagnosis?.severity == .informational || $0.diagnosis == nil }
    }
    private var lastReboot: CrashLog? { reboots.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .foregroundStyle(.red)
                Text("Reboot Events")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(reboots.count) total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Hardware vs Software breakdown
            HStack(spacing: 12) {
                RebootTypeChip(
                    label: "Hardware cause",
                    count: hardwareReboots.count,
                    color: hardwareReboots.isEmpty ? .secondary : .red
                )
                RebootTypeChip(
                    label: "Software / unknown",
                    count: softwareReboots.count,
                    color: softwareReboots.isEmpty ? .secondary : .orange
                )
            }

            // Last reboot info
            if let last = lastReboot {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Last reboot: \(last.timestamp.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let diag = last.diagnosis {
                        Text("— \(diag.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            // Top reboot patterns
            let rebootPatterns = topPatterns()
            if !rebootPatterns.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Root causes")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                    ForEach(rebootPatterns.prefix(3), id: \.title) { item in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(item.severity == .critical || item.severity == .hardware ? Color.red : Color.orange)
                                .frame(width: 6, height: 6)
                            Text(item.title)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text("\(item.count)×")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.red.opacity(0.2), lineWidth: 1))
    }

    private func topPatterns() -> [(title: String, count: Int, severity: Severity)] {
        var counts: [String: (title: String, count: Int, severity: Severity)] = [:]
        for r in reboots {
            if let d = r.diagnosis {
                if var existing = counts[d.patternID] {
                    existing.count += 1
                    counts[d.patternID] = existing
                } else {
                    counts[d.patternID] = (d.title, 1, d.severity)
                }
            }
        }
        return counts.values.sorted { $0.count > $1.count }
    }
}

private struct RebootTypeChip: View {
    let label: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1), in: Capsule())
    }
}

// MARK: - StatCard

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    var accent: Color = .secondary

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(accent)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(accent == .secondary ? .primary : accent)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}
