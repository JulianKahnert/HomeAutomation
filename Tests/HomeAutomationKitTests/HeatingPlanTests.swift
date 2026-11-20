//
//  HeatingPlanTests.swift
//  HomeAutomationKit
//

import Foundation
import HAModels
import Testing

struct HeatingPlanTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        return calendar
    }()

    private let plan = HeatingPlan([
        .init(weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday],
              switchPoints: [SwitchPoint(hour: 6, minute: 30, targetInC: 21), SwitchPoint(hour: 22, targetInC: 17)]),
        .init(weekdays: [.saturday, .sunday],
              switchPoints: [SwitchPoint(hour: 8, targetInC: 21), SwitchPoint(hour: 23, targetInC: 17)])
    ])

    /// 2026-11-16 is a Monday.
    private func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        Self.calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)) ?? .distantPast
    }

    @Test("Each weekday group has its own switch points")
    func weekdayGroups() {
        #expect(plan.planTarget(at: date(day: 18, hour: 12), calendar: Self.calendar) == 21)  // Wednesday
        #expect(plan.planTarget(at: date(day: 18, hour: 23), calendar: Self.calendar) == 17)
        #expect(plan.planTarget(at: date(day: 21, hour: 7), calendar: Self.calendar) == 17)   // Saturday, before 08:00
        #expect(plan.planTarget(at: date(day: 21, hour: 8), calendar: Self.calendar) == 21)
    }

    @Test("Before the first switch point of a day the last target of the day before holds")
    func wrapsIntoThePreviousDay() {
        #expect(plan.planTarget(at: date(day: 17, hour: 5), calendar: Self.calendar) == 17)  // Tuesday 05:00, Monday 22:00 set 17
        // Monday 05:00 follows Sunday 23:00
        #expect(plan.planTarget(at: date(day: 16, hour: 5), calendar: Self.calendar) == 17)
    }

    @Test("A switch point is found in exactly its minute")
    func switchPointMinute() {
        #expect(plan.switchPoint(at: date(day: 16, hour: 6, minute: 30), calendar: Self.calendar)?.targetInC == 21)
        #expect(plan.switchPoint(at: date(day: 16, hour: 6, minute: 31), calendar: Self.calendar) == nil)
        #expect(plan.switchPoint(at: date(day: 16, hour: 8), calendar: Self.calendar) == nil)  // only on the weekend
        #expect(plan.switchPoint(at: date(day: 21, hour: 8), calendar: Self.calendar)?.targetInC == 21)
    }

    @Test("A plan without switch points has no target")
    func emptyPlan() {
        #expect(HeatingPlan([]).planTarget(at: date(day: 16, hour: 12), calendar: Self.calendar) == nil)
    }

    @Test("The plan survives the configuration JSON")
    func codable() throws {
        let decoded = try JSONDecoder().decode(HeatingPlan.self, from: JSONEncoder().encode(plan))
        #expect(decoded == plan)
    }
}
