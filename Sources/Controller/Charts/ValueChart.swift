//
//  ValueChart.swift
//  Controller
//

import Charts
import SwiftUI

/// A measurement over time with an optional threshold line and background bands.
struct ValueChart: View {
    let points: [(date: Date, value: Double)]
    let domain: ClosedRange<Date>
    let color: Color
    let unit: String
    var isLogarithmic = false
    var threshold: (value: Double, label: String)?
    var bands: [DateInterval] = []

    var body: some View {
        Chart {
            ForEach(bands, id: \.start) { band in
                RectangleMark(xStart: .value("Start", band.start), xEnd: .value("End", band.end))
                    .foregroundStyle(ChartPalette.night)
            }
            ForEach(points.indices, id: \.self) { index in
                LineMark(
                    x: .value("Time", points[index].date),
                    // The log scale cannot place 0.
                    y: .value(unit, isLogarithmic ? max(points[index].value, 0.1) : points[index].value)
                )
                .foregroundStyle(color)
            }
            if let threshold {
                RuleMark(y: .value("Threshold", threshold.value))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .trailing) {
                        Text(threshold.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(type: isLogarithmic ? .log : .linear)
        .chartYAxisLabel(unit)
        .chartPlotStyle { $0.clipped() }
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .frame(height: 180)
    }
}

#Preview {
    let now = Date()
    ValueChart(
        points: (0..<24).map { (now.addingTimeInterval(Double($0 - 24) * 3_600), Double($0 * $0)) },
        domain: now.addingTimeInterval(-86_400)...now,
        color: .indigo,
        unit: "lx",
        isLogarithmic: true,
        threshold: (60, "Threshold 60 lx")
    )
    .padding()
}
