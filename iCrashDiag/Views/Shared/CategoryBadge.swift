import SwiftUI

struct CategoryBadge: View {
    let category: CrashCategory

    var body: some View {
        Label(category.rawValue, systemImage: category.systemImage)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary)
            .clipShape(Capsule())
    }
}
