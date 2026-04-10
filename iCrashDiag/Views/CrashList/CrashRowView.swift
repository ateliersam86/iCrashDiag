import SwiftUI

struct CrashRowView: View {
    let crash: CrashLog

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(severityColor)
                .frame(width: 4, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(crash.fileName)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(crash.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 4) {
                    CategoryBadge(category: crash.category)

                    if let diag = crash.diagnosis {
                        Text(diag.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if let proc = crash.processName {
                        Text(proc)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var severityColor: Color {
        guard let sev = crash.diagnosis?.severity else { return .secondary.opacity(0.3) }
        switch sev {
        case .critical: return .red
        case .hardware: return .orange
        case .software: return .yellow
        case .informational: return .secondary
        }
    }
}
