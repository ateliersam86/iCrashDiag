import SwiftUI

struct ProbabilityBarsView: View {
    let probabilities: [Probability]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Probabilities")
                .font(.subheadline)
                .fontWeight(.semibold)

            ForEach(Array(probabilities.enumerated()), id: \.offset) { _, prob in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("\(prob.percent)%")
                            .font(.caption)
                            .fontWeight(.bold)
                            .frame(width: 36, alignment: .trailing)
                            .monospacedDigit()

                        Text(prob.cause)
                            .font(.caption)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.quaternary)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.orange.gradient)
                                .frame(width: geo.size.width * CGFloat(prob.percent) / 100)
                        }
                    }
                    .frame(height: 6)

                    Text(prob.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
