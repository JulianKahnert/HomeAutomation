//
//  TimelineChart.swift
//  Controller
//

import Charts
import SwiftUI

/// State lanes (lamp on, motion, window open, …) over a shared time axis.
struct TimelineChart: View {
    struct Lane: Identifiable {
        let label: String
        let color: Color
        let intervals: [DateInterval]
        var id: String { label }
    }

    let lanes: [Lane]
    let domain: ClosedRange<Date>
    var nights: [DateInterval] = []

    var body: some View {
        // Seconds-long motion pulses would vanish on a 24 h axis; keep each bar visible.
        let minimumDuration = domain.upperBound.timeIntervalSince(domain.lowerBound) / 250
        Chart {
            ForEach(nights, id: \.start) { night in
                RectangleMark(xStart: .value("Start", night.start), xEnd: .value("End", night.end))
                    .foregroundStyle(ChartPalette.night)
            }
            ForEach(lanes) { lane in
                ForEach(lane.intervals, id: \.start) { interval in
                    RectangleMark(
                        xStart: .value("Start", interval.start),
                        xEnd: .value("End", max(interval.end, interval.start.addingTimeInterval(minimumDuration))),
                        y: .value("Lane", lane.label),
                        height: .fixed(12)
                    )
                    .foregroundStyle(lane.color)
                    .clipShape(.rect(cornerRadius: 3))
                }
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: lanes.map(\.label))
        .chartPlotStyle { $0.clipped() }
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .frame(height: CGFloat(lanes.count) * 30 + 30)
    }
}

#Preview {
    let now = Date()
    TimelineChart(
        lanes: [
            .init(label: "Worklight", color: .green, intervals: [DateInterval(start: now.addingTimeInterval(-7_200), end: now.addingTimeInterval(-3_600))]),
            .init(label: "Window", color: .orange, intervals: [DateInterval(start: now.addingTimeInterval(-600), duration: 60)])
        ],
        domain: now.addingTimeInterval(-86_400)...now
    )
    .padding()
}
