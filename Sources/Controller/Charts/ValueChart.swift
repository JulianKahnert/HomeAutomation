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
    var bandColor = ChartPalette.night
    var height: CGFloat = 180

    var body: some View {
        Chart {
            ForEach(bands, id: \.start) { band in
                RectangleMark(xStart: .value("Start", band.start), xEnd: .value("End", band.end))
                    .foregroundStyle(bandColor)
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
                    // Leading keeps the label over the night end of the curve instead of across the daylight peak.
                    .annotation(position: .top, alignment: .leading) {
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
            // .aligned keeps the last time label inside the plot instead of clipping it.
            AxisMarks(preset: .aligned) { _ in
                AxisGridLine()
                AxisValueLabel(format: ChartPalette.axisFormat(for: domain))
            }
        }
        .frame(height: height)
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
