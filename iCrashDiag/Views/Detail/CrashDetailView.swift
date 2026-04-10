import SwiftUI

struct CrashDetailView: View {
    let crash: CrashLog
    @Environment(AppViewModel.self) private var viewModel
    @State private var showRaw = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let diag = crash.diagnosis {
                    DiagnosisCardView(diagnosis: diag)
                    ProbabilityBarsView(probabilities: diag.probabilities)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Repair Steps")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        ForEach(diag.repairSteps, id: \.self) { step in
                            Text(step)
                                .font(.caption)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Test Procedure")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        ForEach(diag.testProcedure, id: \.self) { test in
                            Label(test, systemImage: "checkmark.circle")
                                .font(.caption)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("No known pattern detected", systemImage: "questionmark.circle")
                            .font(.headline)
                        Text("Export the raw data for analysis with an AI tool.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Device Info")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    LabeledContent("Model", value: crash.deviceName ?? crash.deviceModel)
                    LabeledContent("iOS", value: crash.osVersion)
                    LabeledContent("Date", value: crash.timestamp.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("File", value: crash.fileName)
                    LabeledContent("Bug Type", value: "\(crash.bugType)")

                    if !crash.missingSensors.isEmpty {
                        LabeledContent("Missing Sensors", value: crash.missingSensors.joined(separator: ", "))
                    }
                    if let fs = crash.faultingService {
                        LabeledContent("Faulting Service", value: fs)
                    }
                    if let proc = crash.processName {
                        LabeledContent("Process", value: proc)
                    }
                    if let exc = crash.exceptionType {
                        LabeledContent("Exception", value: exc)
                    }
                    if let gpu = crash.gpuRestartReason {
                        LabeledContent("GPU Reason", value: gpu)
                    }
                    if let err = crash.restoreError {
                        LabeledContent("Restore Error", value: "\(err)")
                    }
                    if let lp = crash.largestProcess {
                        LabeledContent("Largest Process", value: lp)
                    }
                }
                .font(.caption)

                Divider()

                HStack {
                    Button("Copy Report") {
                        copySingleCrashReport()
                    }
                    .buttonStyle(.bordered)

                    Button(showRaw ? "Hide Raw Data" : "Show Raw Data") {
                        showRaw.toggle()
                    }
                    .buttonStyle(.bordered)
                }

                if showRaw {
                    let highlights = crash.missingSensors + [crash.faultingService].compactMap { $0 }
                    RawPanicView(
                        text: crash.panicString ?? crash.rawBody,
                        highlights: highlights
                    )
                    .frame(minHeight: 200, maxHeight: 400)
                }
            }
            .padding()
        }
    }

    private func copySingleCrashReport() {
        var md = "# Crash Report: \(crash.fileName)\n\n"
        md += "- **Category**: \(crash.category.rawValue)\n"
        md += "- **Device**: \(crash.deviceName ?? crash.deviceModel)\n"
        md += "- **iOS**: \(crash.osVersion)\n"
        md += "- **Date**: \(crash.timestamp.formatted())\n\n"

        if let diag = crash.diagnosis {
            md += "## Diagnosis\n"
            md += "**\(diag.title)** — \(diag.confidencePercent)% confidence\n"
            md += "Component: \(diag.component)\n\n"
            for p in diag.probabilities {
                md += "- \(p.percent)% — \(p.cause)\n"
            }
            md += "\n### Repair\n"
            for s in diag.repairSteps { md += "\(s)\n" }
        }

        if let ps = crash.panicString {
            md += "\n## Raw Panic String\n```\n\(ps)\n```\n"
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)
    }
}
