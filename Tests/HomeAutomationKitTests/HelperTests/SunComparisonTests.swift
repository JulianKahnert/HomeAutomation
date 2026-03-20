//
//  SunComparisonTests.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 20.03.26.
//

import Foundation
@testable import HAModels
import Testing

struct SunComparisonTests {

    // Oldenburg, Germany
    private let latitude = 53.14194
    private let longitude = 8.21292
    private let timeZone = TimeZone(identifier: "Europe/Berlin")!

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int = 0) throws -> Date {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)))
    }

    private func sunriseComponents(year: Int, month: Int, day: Int) throws -> (hour: Int, minute: Int) {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let refDate = try date(year: year, month: month, day: day, hour: 12, minute: 0)
        let schedule = try #require(Sun.schedule(latitude: latitude, longitude: longitude, date: refDate, calendar: calendar, timeZone: timeZone))
        let sunrise = try #require(schedule.sunrise)
        return (calendar.component(.hour, from: sunrise.date), calendar.component(.minute, from: sunrise.date))
    }

    // MARK: - sunriseElevation

    @Test("Well before sunrise returns .below")
    func wellBeforeSunrise() throws {
        let testDate = try date(year: 2026, month: 3, day: 20, hour: 4, minute: 0)
        #expect(Sun.sunriseElevation(for: testDate, latitude: latitude, longitude: longitude, timeZone: timeZone) == .below)
    }

    @Test("One minute before sunrise returns .below")
    func oneMinuteBeforeSunrise() throws {
        let (h, m) = try sunriseComponents(year: 2026, month: 3, day: 20)
        let testDate = try date(year: 2026, month: 3, day: 20, hour: h, minute: m - 1)
        #expect(Sun.sunriseElevation(for: testDate, latitude: latitude, longitude: longitude, timeZone: timeZone) == .below)
    }

    @Test("Same minute as sunrise returns .horizon")
    func sameMinuteAsSunrise() throws {
        let (h, m) = try sunriseComponents(year: 2026, month: 3, day: 20)
        let testDate = try date(year: 2026, month: 3, day: 20, hour: h, minute: m)
        #expect(Sun.sunriseElevation(for: testDate, latitude: latitude, longitude: longitude, timeZone: timeZone) == .horizon)
    }

    @Test("One minute after sunrise returns .above")
    func oneMinuteAfterSunrise() throws {
        let (h, m) = try sunriseComponents(year: 2026, month: 3, day: 20)
        let testDate = try date(year: 2026, month: 3, day: 20, hour: h, minute: m + 1)
        #expect(Sun.sunriseElevation(for: testDate, latitude: latitude, longitude: longitude, timeZone: timeZone) == .above)
    }

    @Test("Well after sunrise returns .above")
    func wellAfterSunrise() throws {
        let testDate = try date(year: 2026, month: 3, day: 20, hour: 10, minute: 0)
        #expect(Sun.sunriseElevation(for: testDate, latitude: latitude, longitude: longitude, timeZone: timeZone) == .above)
    }

    // MARK: - Edge case: spring equinox (sunrise close to 06:30)

    @Test("Spring equinox: automation at sunrise+1min must not be .below")
    func springEquinoxEdgeCase() throws {
        let (h, m) = try sunriseComponents(year: 2026, month: 3, day: 20)
        let automationDate = try date(year: 2026, month: 3, day: 20, hour: h, minute: m + 1)
        let result = Sun.sunriseElevation(for: automationDate, latitude: latitude, longitude: longitude, timeZone: timeZone)
        #expect(result != .below, "Automation at \(h):\(m + 1) must not trigger when sunrise is at \(h):\(m)")
    }

    // MARK: - Seconds precision: both :00 and :59 of the same minute yield identical results

    @Test("Seconds within sunrise minute do not affect result")
    func secondsWithinSunriseMinute() throws {
        let (h, m) = try sunriseComponents(year: 2026, month: 3, day: 20)
        let atSecond0 = try date(year: 2026, month: 3, day: 20, hour: h, minute: m, second: 0)
        let atSecond15 = try date(year: 2026, month: 3, day: 20, hour: h, minute: m, second: 15)
        let atSecond55 = try date(year: 2026, month: 3, day: 20, hour: h, minute: m, second: 55)
        #expect(Sun.sunriseElevation(for: atSecond0, latitude: latitude, longitude: longitude, timeZone: timeZone) == .horizon)
        #expect(Sun.sunriseElevation(for: atSecond15, latitude: latitude, longitude: longitude, timeZone: timeZone) == .horizon)
        #expect(Sun.sunriseElevation(for: atSecond55, latitude: latitude, longitude: longitude, timeZone: timeZone) == .horizon)
    }

    @Test("Seconds at boundary: last second before sunrise minute is still .below")
    func secondsAtSunriseBoundary() throws {
        let (h, m) = try sunriseComponents(year: 2026, month: 3, day: 20)
        let lastSecondBefore = try date(year: 2026, month: 3, day: 20, hour: h, minute: m - 1, second: 55)
        #expect(Sun.sunriseElevation(for: lastSecondBefore, latitude: latitude, longitude: longitude, timeZone: timeZone) == .below)

        let firstSecondAfter = try date(year: 2026, month: 3, day: 20, hour: h, minute: m + 1, second: 15)
        #expect(Sun.sunriseElevation(for: firstSecondAfter, latitude: latitude, longitude: longitude, timeZone: timeZone) == .above)
    }

    // MARK: - sunsetElevation

    @Test("Before sunset returns .above")
    func beforeSunset() throws {
        let testDate = try date(year: 2026, month: 3, day: 20, hour: 12, minute: 0)
        #expect(Sun.sunsetElevation(for: testDate, latitude: latitude, longitude: longitude, timeZone: timeZone) == .above)
    }

    @Test("After sunset returns .below")
    func afterSunset() throws {
        let testDate = try date(year: 2026, month: 3, day: 20, hour: 22, minute: 0)
        #expect(Sun.sunsetElevation(for: testDate, latitude: latitude, longitude: longitude, timeZone: timeZone) == .below)
    }
}
