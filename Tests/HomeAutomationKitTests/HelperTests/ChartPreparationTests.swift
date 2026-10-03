//
//  ChartPreparationTests.swift
//  HomeAutomationKit
//

import Foundation
import HAModels
import Testing

struct StateIntervalsTests {
    private let start = Date(timeIntervalSince1970: 100_000)
    private var end: Date { start.addingTimeInterval(1_000) }

    private func item(_ offset: TimeInterval, _ isOn: Bool?) -> EntityHistoryItem {
        EntityHistoryItem(timestamp: start.addingTimeInterval(offset), isDeviceOn: isOn)
    }

    @Test func previousStateStartsAtLeftEdgeAndOpenEndClosesAtTo() {
        // Server order: newest first, the includePrevious item appended last.
        let items = [item(800, true), item(500, false), item(100, true), item(-3_600, true)]

        let intervals = StateIntervals.intervals(items: items, isActive: \.isDeviceOn, from: start, to: end)

        #expect(intervals == [
            DateInterval(start: start, end: start.addingTimeInterval(500)),
            DateInterval(start: start.addingTimeInterval(800), end: end)
        ])
    }

    @Test func itemsWithoutTheStateAreIgnored() {
        let items = [item(100, true), item(200, nil), item(300, false)]

        let intervals = StateIntervals.intervals(items: items, isActive: \.isDeviceOn, from: start, to: end)

        #expect(intervals == [DateInterval(start: start.addingTimeInterval(100), end: start.addingTimeInterval(300))])
    }

    @Test func intervalEndingBeforeTheRangeIsDropped() {
        let items = [item(-200, true), item(-100, false)]

        #expect(StateIntervals.intervals(items: items, isActive: \.isDeviceOn, from: start, to: end).isEmpty)
    }
}

struct NightsTests {
    @Test func nightsCoverMidnightButNotNoon() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let midnight = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 2)))
        let range = DateInterval(start: midnight.addingTimeInterval(-6 * 3600), end: midnight.addingTimeInterval(18 * 3600))

        let nights = StateIntervals.nights(in: range, latitude: 52.5, longitude: 13.4, calendar: calendar)

        #expect(nights.count == 1)
        #expect(nights.contains { $0.contains(midnight) })
        #expect(!nights.contains { $0.contains(midnight.addingTimeInterval(12 * 3600)) })
    }
}

struct DailyTotalsTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }
    private let day1 = Date(timeIntervalSince1970: 86_400 * 10)
    private var day2: Date { day1.addingTimeInterval(86_400) }

    @Test func intervalAcrossMidnightIsSplitBetweenDays() {
        let interval = DateInterval(start: day2.addingTimeInterval(-600), end: day2.addingTimeInterval(300))

        let totals = DailyTotals.dailyTotals([interval], days: [day1, day2], calendar: calendar)

        #expect(totals.map(\.day) == [day1, day2])
        #expect(totals.map(\.duration) == [600, 300])
    }

    @Test func countsPerDayBucketsDates() {
        let dates = [day1.addingTimeInterval(10), day1.addingTimeInterval(20), day2.addingTimeInterval(5), day2.addingTimeInterval(86_400)]

        let counts = DailyTotals.countsPerDay(dates, days: [day1, day2], calendar: calendar)

        #expect(counts.map(\.count) == [2, 1])
    }
}

struct RunStatisticsTests {
    private let motion = EntityId(placeId: "Hallway", name: "Eve Motion", characteristicsName: nil, characteristic: .motionSensor)
    private let start = Date(timeIntervalSince1970: 86_400 * 10)

    private func run(_ trigger: AutomationTrigger, _ outcome: AutomationRun.Outcome, at offset: TimeInterval = 0) -> AutomationRun {
        AutomationRun(automationName: "Night", startedAt: start.addingTimeInterval(offset), trigger: trigger, outcome: outcome)
    }

    private var runs: [AutomationRun] {
        let byMotion = AutomationTrigger(kind: .entityChange, entityId: motion, summary: "Motion · Eve Motion (Hallway)")
        let bySunset = AutomationTrigger(kind: .sunset, entityId: nil, summary: "Sunset · Lights on")
        return [run(byMotion, .completed), run(byMotion, .failed, at: 86_400), run(bySunset, .completed, at: 60)]
    }

    @Test func byTriggerGroupsByEntityOrSummaryPrefixMostFirst() {
        let groups = RunStatistics.byTrigger(runs)

        #expect(groups.map(\.trigger) == ["Eve Motion", "Sunset"])
        #expect(groups.map(\.count) == [2, 1])
    }

    @Test func byOutcomeCountsEachOutcome() {
        #expect(RunStatistics.byOutcome(runs) == [.completed: 2, .failed: 1])
    }

    @Test func perDayCountsRunStarts() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt

        let counts = RunStatistics.perDay(runs, days: [start, start.addingTimeInterval(86_400)], calendar: calendar)

        #expect(counts.map(\.count) == [2, 1])
    }
}
