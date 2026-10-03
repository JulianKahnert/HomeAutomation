//
//  DailyBarChart.swift
//  Controller
//

import Charts
import SwiftUI

/// One bar per day, with an optional point per day (e.g. the mean on top of the maximum).
struct DailyBarChart: View {
    let bars: [(day: Date, value: Double)]
    let color: Color
    let unit: String
    var points: [(day: Date, value: Double)] = []

    var body: some View {
        Chart {
            ForEach(bars.indices, id: \.self) { index in
                BarMark(x: .value("Day", bars[index].day, unit: .day), y: .value(unit, bars[index].value))
                    .foregroundStyle(color)
            }
            ForEach(points.indices, id: \.self) { index in
                PointMark(x: .value("Day", points[index].day, unit: .day), y: .value(unit, points[index].value))
                    .foregroundStyle(.primary)
            }
        }
        .chartYAxisLabel(unit)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
            }
        }
        .frame(height: 140)
    }
}

#Preview {
    DailyBarChart(
        bars: (0..<7).map { (Date().addingTimeInterval(Double($0 - 6) * 86_400), Double($0 * 10)) },
        color: .orange,
        unit: "min"
    )
    .padding()
}
