import SwiftUI

struct CrashDetailView: View {
    let crash: CrashLog
    @Environment(AppViewModel.self) private var viewModel
    @State private var showRaw = false
    @State private var showShareSheet = false
    @State private var isSubmittingUnknown = false
    @State private var unknownSubmitted = false
    @State private var feedbackSent: Bool? = nil   // nil=not sent, true=helpful, false=not helpful

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let diag = crash.diagnosis {
                    DiagnosisCardView(diagnosis: diag)
                    ProbabilityBarsView(probabilities: diag.probabilities)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Repair Steps", bundle: .module)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        ForEach(diag.repairSteps, id: \.self) { step in
                            Text(step)
                                .font(.caption)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Test Procedure", bundle: .module)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        ForEach(diag.testProcedure, id: \.self) { test in
                            Label(test, systemImage: "checkmark.circle")
                                .font(.caption)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("No known pattern detected", systemImage: "questionmark.circle")
                            .font(.headline)
                        Text("Export the raw data for analysis with an AI tool.", bundle: .module)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        // Submit unknown button
                        Button {
                            Task { await submitUnknownPattern() }
                        } label: {
                            if isSubmittingUnknown {
                                ProgressView().controlSize(.small)
                            } else if unknownSubmitted {
                                Label("Submitted — thanks!", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Label("Submit to improve the knowledge base", systemImage: "arrow.up.circle")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isSubmittingUnknown || unknownSubmitted)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                }

                // Feedback row (only when diagnosis exists and confidence is meaningful)
                if let diag = crash.diagnosis, diag.confidencePercent >= 20 {
                    HStack(spacing: 6) {
                        Text("Was this diagnosis helpful?", bundle: .module)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let sent = feedbackSent {
                            Label(sent ? "Helpful" : "Not helpful", systemImage: sent ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                                .font(.caption2)
                                .foregroundStyle(sent ? .green : .orange)
                        } else {
                            Button { Task { await sendFeedback(helpful: true) } } label: {
                                Image(systemName: "hand.thumbsup")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            Button { Task { await sendFeedback(helpful: false) } } label: {
                                Image(systemName: "hand.thumbsdown")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    }
                    .padding(.horizontal, 4)
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Device Info", bundle: .module)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    let modelLabel = crash.deviceName
                        ?? (crash.deviceModel == "Unknown" ? nil : crash.deviceModel)
                        ?? "Unknown"
                    LabeledContent("Model", value: modelLabel)
                    LabeledContent("iOS", value: crash.osVersion)
                    if let build = crash.buildVersion {
                        LabeledContent("Build", value: build)
                    }
                    LabeledContent("Date", value: crash.timestamp.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("File", value: crash.fileName)
                    LabeledContent("Category", value: crash.category.rawValue)
                }
                .font(.caption)

                // Category-specific details
                let hasCategoryDetails = !crash.missingSensors.isEmpty
                    || crash.faultingService != nil
                    || crash.processName != nil
                    || crash.exceptionType != nil
                    || crash.terminationReason != nil
                    || crash.gpuRestartReason != nil
                    || crash.restoreError != nil
                    || crash.largestProcess != nil
                    || crash.freePages != nil

                if hasCategoryDetails {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Crash Details", bundle: .module)
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        if let proc = crash.processName {
                            LabeledContent(crash.category == .jetsam ? "Killed Process" : "Process", value: proc)
                        }
                        if let exc = crash.exceptionType {
                            LabeledContent("Exception", value: exc)
                        }
                        if let term = crash.terminationReason {
                            LabeledContent("Termination", value: term)
                        }
                        if !crash.missingSensors.isEmpty {
                            LabeledContent("Missing Sensors", value: crash.missingSensors.joined(separator: ", "))
                        }
                        if let fs = crash.faultingService {
                            let label = crash.category == .jetsam ? "Jetsam Reason"
                                : crash.category == .thermal ? "Thermal State"
                                : "Faulting Service"
                            LabeledContent(label, value: fs)
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
                        if let fp = crash.freePages {
                            LabeledContent("Free Memory Pages", value: "\(fp)")
                        }
                    }
                    .font(.caption)
                }

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

                    Spacer()

                    Button {
                        showShareSheet = true
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }
                .sheet(isPresented: $showShareSheet) {
                    ShareCrashView(crash: crash)
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

    private func submitUnknownPattern() async {
        isSubmittingUnknown = true
        let ok = await CommunityService.shared.submitUnknown(crash)
        await MainActor.run {
            isSubmittingUnknown = false
            unknownSubmitted = ok
        }
    }

    private func sendFeedback(helpful: Bool) async {
        guard let patternID = crash.diagnosis?.patternID else { return }
        await CommunityService.shared.submitFeedback(patternID: patternID, helpful: helpful, crash: crash)
        await MainActor.run { feedbackSent = helpful }
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
