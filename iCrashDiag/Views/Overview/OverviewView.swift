import SwiftUI

struct OverviewView: View {
    let report: AnalysisReport
    @Environment(AppViewModel.self) private var viewModel
    @State private var exportError: String?

    // MARK: - Computed helpers

    private var hwPatternCount: Int {
        report.topPatterns.filter { $0.severity == .hardware || $0.severity == .critical }
            .map(\.count).reduce(0, +)
    }

    private var crashesPerDayAvg: String {
        guard let dr = report.dateRange else { return "—" }
        let days = max(1, Calendar.current.dateComponents([.day], from: dr.start, to: dr.end).day ?? 1)
        let avg = Double(report.totalCrashes) / Double(days)
        return avg < 1 ? "<1" : String(format: "%.1f", avg)
    }

    private var topDevice: String? {
        report.deviceModels.max(by: { $0.value < $1.value })?.key
    }

    private var categoryRows: [(name: String, count: Int, color: Color)] {
        let total = report.categoryBreakdown.values.reduce(0, +)
        guard total > 0 else { return [] }
        return report.categoryBreakdown
            .sorted { $0.value > $1.value }
            .prefix(6)
            .map { key, val in
                let cat = CrashCategory(rawValue: key) ?? .unknown
                let color: Color = switch cat {
                    case .kernelPanic:  .red
                    case .jetsam:       .orange
                    case .watchdog:     .yellow
                    case .appCrash:     .blue
                    case .thermal:      .purple
                    case .gpuEvent:     .mint
                    case .diskResource: .brown
                    default:            .secondary
                }
                return (name: key, count: val, color: color)
            }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {

                // ── HERO — Verdict ───────────────────────────────────────────
                let isHW = report.overallVerdict.isHardware
                let verdictColor: Color = isHW ? .orange : .green

                ZStack(alignment: .trailing) {
                    // Background tint
                    RoundedRectangle(cornerRadius: 16)
                        .fill(verdictColor.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(verdictColor.opacity(0.22), lineWidth: 1))

                    // Big confidence number (decorative, right-aligned)
                    Text("\(report.overallVerdict.confidence)%")
                        .font(.system(size: 72, weight: .black, design: .rounded))
                        .foregroundStyle(verdictColor.opacity(0.08))
                        .padding(.trailing, 20)

                    HStack(spacing: 16) {
                        // Icon
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(verdictColor.opacity(0.15))
                                .frame(width: 56, height: 56)
                            Image(systemName: isHW ? "wrench.and.screwdriver.fill" : "checkmark.circle.fill")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(verdictColor)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(isHW ? "Hardware Issue Detected" : "No Hardware Issue")
                                .font(.title3).fontWeight(.bold)
                                .foregroundStyle(verdictColor)
                            Text(report.overallVerdict.summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            // Meta line
                            HStack(spacing: 10) {
                                if let dr = report.dateRange {
                                    Label(dr.start.formatted(date: .abbreviated, time: .omitted)
                                          + " – " + dr.end.formatted(date: .abbreviated, time: .omitted),
                                          systemImage: "calendar")
                                }
                                if let dev = topDevice {
                                    Label(dev, systemImage: "iphone")
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                        }

                        Spacer()

                        VStack(spacing: 2) {
                            Text("\(report.overallVerdict.confidence)%")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundStyle(verdictColor)
                                .monospacedDigit()
                            Text("confidence", bundle: .module)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(18)
                }

                // ── STAT TILES ───────────────────────────────────────────────
                HStack(spacing: 10) {
                    BigStatTile(value: "\(report.totalCrashes)", label: "Total Crashes",
                                icon: "doc.text.fill", color: .primary)
                    BigStatTile(value: "\(hwPatternCount)", label: "Hardware Events",
                                icon: "wrench.fill", color: hwPatternCount > 0 ? .orange : .secondary)
                    BigStatTile(value: "\(viewModel.rebootCount)", label: "Reboots",
                                icon: "arrow.clockwise.circle.fill",
                                color: viewModel.rebootCount > 0 ? .red : .secondary)
                    BigStatTile(value: crashesPerDayAvg, label: "Per Day",
                                icon: "chart.bar.fill", color: .blue)
                    BigStatTile(value: "\(report.topPatterns.count)", label: "Patterns",
                                icon: "magnifyingglass", color: .purple)
                }

                // ── MAIN GRID — 2 columns ────────────────────────────────────
                HStack(alignment: .top, spacing: 12) {

                    // LEFT — Timeline + Category breakdown
                    VStack(spacing: 12) {

                        // Timeline
                        if !report.crashesPerDay.isEmpty {
                            DashboardCard(title: "Crash Timeline", icon: "chart.xyaxis.line") {
                                TimelineChartView(crashesPerDay: report.crashesPerDay)
                                    .frame(height: 90)
                            }
                        }

                        // Category breakdown — horizontal bars
                        if !categoryRows.isEmpty {
                            DashboardCard(title: "By Category", icon: "square.grid.2x2") {
                                let total = categoryRows.map(\.count).reduce(0, +)
                                VStack(spacing: 8) {
                                    ForEach(categoryRows, id: \.name) { row in
                                        VStack(spacing: 3) {
                                            HStack {
                                                Text(row.name)
                                                    .font(.caption)
                                                    .lineLimit(1)
                                                Spacer()
                                                Text("\(row.count)")
                                                    .font(.caption)
                                                    .fontWeight(.semibold)
                                                    .monospacedDigit()
                                                    .foregroundStyle(.secondary)
                                                Text("(\(Int(Double(row.count)/Double(total)*100))%)")
                                                    .font(.caption2)
                                                    .foregroundStyle(.tertiary)
                                                    .frame(width: 34, alignment: .trailing)
                                            }
                                            GeometryReader { geo in
                                                ZStack(alignment: .leading) {
                                                    RoundedRectangle(cornerRadius: 3)
                                                        .fill(Color.secondary.opacity(0.1))
                                                    RoundedRectangle(cornerRadius: 3)
                                                        .fill(row.color.opacity(0.75))
                                                        .frame(width: geo.size.width * Double(row.count) / Double(total))
                                                }
                                            }
                                            .frame(height: 5)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // RIGHT — Diagnosis + Hardware gauge + Top patterns
                    VStack(spacing: 12) {

                        if let diag = report.dominantDiagnosis {
                            DiagnosisCardView(diagnosis: diag)
                        }

                        HardwareGaugeView(report: report)

                        if !report.topPatterns.isEmpty {
                            DashboardCard(title: "Top Patterns", icon: "list.number") {
                                VStack(spacing: 5) {
                                    ForEach(report.topPatterns.prefix(5)) { p in
                                        HStack(spacing: 6) {
                                            SeverityBadge(severity: p.severity)
                                            Text(p.title).font(.caption).lineLimit(1)
                                            Spacer()
                                            Text("\(p.count)×")
                                                .font(.caption).fontWeight(.bold)
                                                .monospacedDigit().foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }

                        let reboots = viewModel.rebootEvents
                        if !reboots.isEmpty {
                            RebootDashboardCard(reboots: reboots)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                // ── FOOTER — spread + export ─────────────────────────────────
                if isHW && report.overallVerdict.confidence >= 70 {
                    SpreadWordBanner()
                }

                let isPro = viewModel.licenseService.isPro
                HStack {
                    Button(isPro ? "Copy Report" : "Copy Report (Pro)") {
                        viewModel.copyReportToClipboard()
                    }
                    .buttonStyle(.borderedProminent).tint(.orange)
                    Button(isPro ? "Export JSON…" : "Export JSON… (Pro)") {
                        if isPro { exportJSON() } else { viewModel.showLicenseGate = true }
                    }.buttonStyle(.bordered)
                    Button(isPro ? "Export Markdown…" : "Export Markdown… (Pro)") {
                        if isPro { exportMarkdown() } else { viewModel.showLicenseGate = true }
                    }.buttonStyle(.bordered)
                    Spacer()
                }
            }
            .padding(16)
        }
        .alert("Export Failed", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "iCrashDiag-report.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let includeRaw = AppSettings.shared.exportIncludeRawBody
        do {
            let data = try viewModel.exportService.generateJSON(crashes: viewModel.crashLogs, report: report, includeRawBody: includeRaw)
            try data.write(to: url)
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func exportMarkdown() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "iCrashDiag-report.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let md = viewModel.exportService.generateMarkdown(crashes: viewModel.crashLogs, report: report)
        do {
            try md.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            exportError = error.localizedDescription
        }
    }
}

// MARK: - DashboardCard

private struct DashboardCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Spread the Word Banner

private struct SpreadWordBanner: View {
    @AppStorage("iCrashDiag.spreadWordDismissed") private var dismissed = false

    var body: some View {
        if !dismissed {
            HStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Found a hardware issue?", bundle: .module)
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("Share iCrashDiag with your repair community — it's free to try.", bundle: .module)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismissed = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Dismiss"))
            }
            .padding(10)
            .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.orange.opacity(0.2), lineWidth: 1))
        }
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
                Text("Hardware Risk", bundle: .module)
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
                Text("Low risk", bundle: .module).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("High risk", bundle: .module).font(.caption2).foregroundStyle(.secondary)
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
                Text("Reboot Events", bundle: .module)
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
                    Text("Root causes", bundle: .module)
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

// MARK: - BigStatTile

private struct BigStatTile: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(color == .primary ? Color.secondary : color)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - StatCard

private struct StatCard: View {
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
