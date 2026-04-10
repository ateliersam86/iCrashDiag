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

                HStack(spacing: 16) {
                    StatCard(title: "Total Crashes", value: "\(report.totalCrashes)", icon: "doc.text.fill")
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

struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .monospacedDigit()
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}
