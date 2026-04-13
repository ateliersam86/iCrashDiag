import SwiftUI

struct CrashRowView: View {
    let crash: CrashLog
    var isLocked: Bool = false
    @State private var appeared = false

    var body: some View {
        ZStack {
            // Normal row content (always rendered)
            rowContent
                .blur(radius: isLocked ? 3.5 : 0)
                .opacity(isLocked ? 0.55 : 1)

            // Lock overlay
            if isLocked {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Pro", bundle: .module)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.regularMaterial, in: Capsule())
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 4)
            }
        }
        .padding(.vertical, 3)
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : 8)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8).delay(0.02)) {
                appeared = true
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(severityColor)
                .frame(width: 3, height: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 0) {
                    Text(crash.fileName)
                        .font(.system(size: 12, design: .default))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(crash.timestamp, style: .time)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 5) {
                    CategoryBadge(category: crash.category)

                    if let diag = crash.diagnosis {
                        Text(diag.title)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        let subtitle = crash.processName
                            ?? crash.deviceName
                            ?? (crash.deviceModel == "Unknown" ? nil : crash.deviceModel)
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    if !isLocked, let conf = crash.diagnosis?.confidencePercent {
                        Text("\(conf)%")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(conf >= 80 ? .orange : .secondary)
                    }
                    if !isLocked, let sev = crash.diagnosis?.severity, sev == .critical || sev == .hardware {
                        Image(systemName: sev == .critical ? "exclamationmark.triangle.fill" : "wrench.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(sev == .critical ? .red : .orange)
                    }
                }
            }
        }
    }

    private var severityColor: Color {
        guard let sev = crash.diagnosis?.severity else { return Color.secondary.opacity(0.2) }
        switch sev {
        case .critical:      return .red
        case .hardware:      return .orange
        case .software:      return .yellow
        case .informational: return Color.secondary.opacity(0.3)
        }
    }
}
