//
//  DatabaseCleanupTests.swift
//  HomeAutomationKit
//

import Foundation
import HAImplementations
import HAModels
import Testing

@HomeManagerActor
struct DatabaseCleanupTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(hour: Int, minute: Int) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: hour, minute: minute))!
    }

    @Test func serverStartRunsEveryStep() {
        #expect(DatabaseCleanup.steps(for: .serverStarted, calendar: utc) == StorageUpkeepStep.allCases)
    }

    @Test func theClockRollsUpEveryFullHourAndCleansUpDaily() {
        #expect(DatabaseCleanup.steps(for: .time(date: date(hour: 10, minute: 0)), calendar: utc) == [.rollup])
        #expect(DatabaseCleanup.steps(for: .time(date: date(hour: DatabaseCleanup.cleanupHour, minute: 0)), calendar: utc) == [.rollup, .cleanup, .journal])
        #expect(DatabaseCleanup.steps(for: .time(date: date(hour: 10, minute: 1)), calendar: utc).isEmpty)
        #expect(DatabaseCleanup.steps(for: .sunrise, calendar: utc).isEmpty)
    }

    @Test func executeRunsTheStepsOfTheTriggeringEventThroughTheFacade() async throws {
        let homeManager = MockHomeAdapter()

        try await AutomationRunContext.$event.withValue(.serverStarted) {
            try await DatabaseCleanup().execute(using: homeManager)
        }

        #expect(homeManager.upkeepSteps == StorageUpkeepStep.allCases)
    }

    @Test func doesNotCutARunningRun() {
        #expect(DatabaseCleanup().supersedesRunningRun == false)
    }
}
