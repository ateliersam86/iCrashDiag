import SwiftUI

extension Severity {
    var badgeColor: Color {
        switch self {
        case .critical:      return Color(red: 0.95, green: 0.20, blue: 0.20)
        case .hardware:      return Color(red: 1.00, green: 0.50, blue: 0.08)
        case .software:      return Color(red: 0.90, green: 0.72, blue: 0.06)
        case .informational: return Color.secondary
        }
    }
    var badgeIcon: String {
        switch self {
        case .critical:      return "exclamationmark.triangle.fill"
        case .hardware:      return "wrench.fill"
        case .software:      return "ant.fill"
        case .informational: return "info.circle.fill"
        }
    }
}

struct SeverityBadge: View {
    let severity: Severity

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: severity.badgeIcon)
                .font(.system(size: 9, weight: .bold))
            Text(severity.rawValue.capitalized)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(severity.badgeColor)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(severity.badgeColor.opacity(0.13), in: Capsule())
    }
}
