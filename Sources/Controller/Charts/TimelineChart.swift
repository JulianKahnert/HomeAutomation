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
        /// Legend entry; lanes without one keep the chart legend hidden.
        var kind: String?
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
                RectangleMark(xStart: .value(ChartLabel.start, night.start), xEnd: .value(ChartLabel.end, night.end))
                    .foregroundStyle(ChartPalette.night)
            }
            ForEach(lanes) { lane in
                ForEach(lane.intervals, id: \.start) { interval in
                    RectangleMark(
                        xStart: .value(ChartLabel.start, interval.start),
                        xEnd: .value(ChartLabel.end, max(interval.end, interval.start.addingTimeInterval(minimumDuration))),
                        y: .value(ChartLabel.lane, lane.label),
                        height: .fixed(12)
                    )
                    .foregroundStyle(by: .value(ChartLabel.kind, lane.kind ?? lane.label))
                    .clipShape(.rect(cornerRadius: 3))
                }
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: lanes.map(\.label))
        .chartForegroundStyleScale(domain: legendEntries.map(\.kind), range: legendEntries.map(\.color))
        .chartLegend(lanes.contains { $0.kind != nil } ? .visible : .hidden)
        .chartPlotStyle { $0.clipped() }
        .chartXAxis {
            // .aligned keeps the last time label inside the plot instead of clipping it.
            AxisMarks(preset: .aligned) { _ in
                AxisGridLine()
                AxisValueLabel(format: ChartPalette.axisFormat(for: domain))
            }
        }
        .frame(height: CGFloat(lanes.count) * 30 + (lanes.contains { $0.kind != nil } ? 54 : 30))
    }

    private var legendEntries: [(kind: String, color: Color)] {
        var seen = Set<String>()
        return lanes.compactMap { lane in
            let kind = lane.kind ?? lane.label
            return seen.insert(kind).inserted ? (kind, lane.color) : nil
        }
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
