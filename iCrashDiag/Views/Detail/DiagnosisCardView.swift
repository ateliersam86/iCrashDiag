import SwiftUI

struct DiagnosisCardView: View {
    let diagnosis: Diagnosis

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SeverityBadge(severity: diagnosis.severity)
                Text("\(diagnosis.confidencePercent)% confidence")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(diagnosis.title)
                .font(.headline)

            Text(diagnosis.component)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(severityColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(severityColor.opacity(0.3), lineWidth: 1)
                )
        }
    }

    private var severityColor: Color {
        switch diagnosis.severity {
        case .critical: .red
        case .hardware: .orange
        case .software: .yellow
        case .informational: .secondary
        }
    }
}
