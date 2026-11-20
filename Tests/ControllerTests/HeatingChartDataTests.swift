//
//  HeatingChartDataTests.swift
//  ControllerTests
//

@testable import Controller
import Foundation
import HAModels
import Testing

@Suite("HeatingChartData")
struct HeatingChartDataTests {
    private func sample(_ minute: Int, ist: Double?, plan: Double? = 21, valves: [Double?] = [nil]) -> HeatingSample {
        HeatingSample(date: Date(timeIntervalSince1970: Double(minute) * 60), ist: ist, sollPlan: plan, valves: valves)
    }

    @Test("a missing actual value splits the line into runs")
    func gapSplitsRuns() {
        let runs = HeatingChartData.istRuns([sample(0, ist: 20), sample(5, ist: 20.5), sample(10, ist: nil), sample(15, ist: 21)])
        #expect(runs.map(\.count) == [2, 1])
    }

    @Test("valve runs follow one radiator and split while it is silent")
    func valveRuns() {
        let samples = [sample(0, ist: 20, valves: [10, 50]), sample(5, ist: 20, valves: [nil, 60]), sample(10, ist: 20, valves: [30, 70])]
        #expect(HeatingChartData.valveRuns(samples, radiator: 0).map(\.count) == [1, 1])
        #expect(HeatingChartData.valveRuns(samples, radiator: 1).map(\.count) == [3])
    }

    @Test("gap segments change at the comfort band edges and close without a hole")
    func gapSegmentsPerColour() {
        let samples = [sample(0, ist: 20.8), sample(5, ist: 21.2), sample(10, ist: 19.0), sample(15, ist: 19.0)]
        let segments = HeatingChartData.gapSegments(samples)
        #expect(segments.map(\.band) == [.ok, .tooCold])
        #expect(segments[0].points.count == 3)
        #expect(segments[1].points.count == 2)
        #expect(segments[0].points.last?.date == segments[1].points.first?.date)
    }

    @Test("a sample without plan or actual value ends the gap segment")
    func gapSegmentsStopAtGaps() {
        let samples = [sample(0, ist: 20), sample(5, ist: 20), sample(10, ist: nil), sample(15, ist: 20), sample(20, ist: 20)]
        #expect(HeatingChartData.gapSegments(samples).count == 2)
    }

    @Test("a room without any actual value draws no plan line")
    func noPlanWithoutIst() {
        #expect(HeatingChartData.planRuns([sample(0, ist: nil), sample(5, ist: nil)]).isEmpty)
        #expect(HeatingChartData.planRuns([sample(0, ist: 20), sample(5, ist: nil)]).count == 1)
    }

    @Test("weekday labels are short German names")
    func weekday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let monday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 0))!
        #expect(HeatingFormat.weekday(monday, calendar: calendar) == "Mo.")
    }

    @Test("the crosshair snaps to the nearest sample")
    func nearest() {
        let samples = [sample(0, ist: 20), sample(5, ist: 21)]
        #expect(HeatingChartData.nearest(to: Date(timeIntervalSince1970: 200), in: samples)?.ist == 21)
    }

    @Test("the temperature domain is at least two kelvin high")
    func domain() {
        let domain = HeatingChartData.temperatureDomain([sample(0, ist: 20, plan: 20)])
        #expect(domain.upperBound - domain.lowerBound >= 2)
    }

    @Test("the comfort band is plus minus half a kelvin, edges included")
    func bandEdges() {
        #expect(HeatingPalette.band(forDelta: -0.5) == .ok)
        #expect(HeatingPalette.band(forDelta: 0.5) == .ok)
        #expect(HeatingPalette.band(forDelta: -0.51) == .tooCold)
        #expect(HeatingPalette.band(forDelta: 0.51) == .tooWarm)
    }

    @Test("numbers use the decimal comma and a real minus")
    func formatting() {
        #expect(HeatingFormat.degrees(21.5) == "21,5°")
        #expect(HeatingFormat.kelvin(1.24) == "+1,2 K")
        #expect(HeatingFormat.kelvin(-0.8) == "−0,8 K")
        #expect(HeatingFormat.kelvin(0.02) == "±0,0 K")
    }
}
