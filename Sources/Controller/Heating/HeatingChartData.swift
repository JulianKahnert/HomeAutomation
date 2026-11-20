//
//  HeatingChartData.swift
//  ControllerFeatures
//
//  Pure preparation of the grid for the charts: runs split at gaps, gap segments per colour
//

import Foundation
import HAModels

enum HeatingChartData {
    struct Point: Equatable, Sendable {
        let date: Date
        let value: Double
    }

    /// The gap between actual value and plan target over a stretch of one colour.
    struct GapSegment: Equatable, Sendable, Identifiable {
        struct Point: Equatable, Sendable {
            let date: Date
            let ist: Double
            let plan: Double
        }

        let id: Int
        let band: HeatingComfort
        let points: [Point]
    }

    /// Contiguous stretches where `value` is not `nil`. A `nil` sample ends a run, so a line is not drawn
    /// across a gap (silence stays visible).
    static func runs(_ samples: [HeatingSample], value: (HeatingSample) -> Double?) -> [[Point]] {
        var result: [[Point]] = []
        var current: [Point] = []
        for sample in samples {
            if let v = value(sample) {
                current.append(Point(date: sample.date, value: v))
            } else if !current.isEmpty {
                result.append(current)
                current = []
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    static func istRuns(_ samples: [HeatingSample]) -> [[Point]] { runs(samples) { $0.ist } }

    /// The plan line; a room without any actual value still has it.
    static func planRuns(_ samples: [HeatingSample]) -> [[Point]] {
        runs(samples) { $0.sollPlan }
    }

    /// The smallest height of a bar in K, so a room at Δ≈0 stays a visible pill.
    static let minimumBarHeight = 0.34

    /// The extent of the Δ bar: from the zero line to Δ, clipped at the ±3 K scale (the bar then runs off the
    /// end), and at least `minimumBarHeight` high (a bar at Δ≈0 is a pill around the zero line).
    static func barExtent(forDelta delta: Double) -> ClosedRange<Double> {
        let clipped = min(max(delta, -HeatingPalette.barScale), HeatingPalette.barScale)
        var low = min(clipped, 0)
        var high = max(clipped, 0)
        if high - low < minimumBarHeight {
            let middle = (low + high) / 2
            low = middle - minimumBarHeight / 2
            high = middle + minimumBarHeight / 2
        }
        return low...high
    }

    static func valveRuns(_ samples: [HeatingSample], radiator: Int) -> [[Point]] {
        runs(samples) { $0.valves.indices.contains(radiator) ? $0.valves[radiator] : nil }
    }

    /// Stretches where both values exist, cut where the colour changes; the first sample of the next
    /// colour closes the previous segment, so no hole shows between two colours.
    static func gapSegments(_ samples: [HeatingSample]) -> [GapSegment] {
        var result: [GapSegment] = []
        var points: [GapSegment.Point] = []
        var band: HeatingComfort?
        let close = {
            if let band, points.count > 1 {
                result.append(GapSegment(id: result.count, band: band, points: points))
            }
        }
        for sample in samples {
            guard let ist = sample.ist, let plan = sample.sollPlan else {
                close()
                points = []
                band = nil
                continue
            }
            let point = GapSegment.Point(date: sample.date, ist: ist, plan: plan)
            let sampleBand = HeatingComfort(delta: ist - plan)
            if let current = band, current != sampleBand {
                points.append(point)
                close()
                points = [point]
            } else {
                points.append(point)
            }
            band = sampleBand
        }
        close()
        return result
    }

    /// The sample closest to `date`.
    static func nearest(to date: Date, in samples: [HeatingSample]) -> HeatingSample? {
        samples.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    /// The x range of both charts: first to last sample.
    static func timeDomain(_ samples: [HeatingSample]) -> ClosedRange<Date> {
        guard let first = samples.first?.date, let last = samples.last?.date else { return Date.now...Date.now.addingTimeInterval(1) }
        return first...max(last, first.addingTimeInterval(1))
    }

    /// The y range of the temperature chart: the data with a margin, at least 2 K high.
    static func temperatureDomain(_ samples: [HeatingSample]) -> ClosedRange<Double> {
        let values = samples.flatMap { [$0.ist, $0.sollPlan].compactMap { $0 } }
        guard let low = values.min(), let high = values.max() else { return 16...24 }
        let margin = max((2 - (high - low)) / 2, 0.5)
        return (low - margin)...(high + margin)
    }
}
