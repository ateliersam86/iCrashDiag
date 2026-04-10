import SwiftUI

struct RawPanicView: View {
    let text: String
    let highlights: [String]

    var body: some View {
        ScrollView {
            Text(attributedText)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .background(.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var attributedText: AttributedString {
        var attr = AttributedString(text)
        for keyword in highlights where !keyword.isEmpty {
            var searchRange = attr.startIndex..<attr.endIndex
            while let range = attr[searchRange].range(of: keyword, options: .caseInsensitive) {
                attr[range].foregroundColor = .red
                attr[range].font = .system(.caption, design: .monospaced).bold()
                if range.upperBound < attr.endIndex {
                    searchRange = range.upperBound..<attr.endIndex
                } else {
                    break
                }
            }
        }
        return attr
    }
}
