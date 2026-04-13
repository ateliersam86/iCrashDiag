import SwiftUI
import Charts

struct TimelineChartView: View {
    let crashesPerDay: [String: Int]

    var body: some View {
        let data = crashesPerDay.sorted(by: { $0.key < $1.key })

        Chart(data, id: \.key) { day, count in
            BarMark(
                x: .value("Date", day),
                y: .value("Crashes", count)
            )
            .foregroundStyle(.orange.gradient)
        }
        .chartXAxis(.hidden)
    }
}
