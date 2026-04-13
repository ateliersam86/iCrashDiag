import SwiftUI

extension CrashCategory {
    var badgeColor: Color {
        switch self {
        case .kernelPanic:   return .red
        case .watchdog:      return .orange
        case .jetsam:        return .purple
        case .appCrash:      return .blue
        case .gpuEvent:      return Color(red: 0.2, green: 0.7, blue: 0.9)
        case .otaUpdate:     return .teal
        case .thermal:       return Color(red: 1.0, green: 0.35, blue: 0.0)
        case .diskResource:  return Color(red: 0.5, green: 0.4, blue: 0.9)
        case .unknown:       return .secondary
        }
    }
}

struct CategoryBadge: View {
    let category: CrashCategory

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: category.systemImage)
                .font(.system(size: 9, weight: .medium))
            Text(category.rawValue)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(category.badgeColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(category.badgeColor.opacity(0.12), in: Capsule())
        .accessibilityLabel(Text("\(category.rawValue) category"))
        .accessibilityElement(children: .ignore)
    }
}
