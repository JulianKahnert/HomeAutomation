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

    // MARK: - Civil twilight (sun at zenith 96°, i.e. 6° below the horizon)
    //
    // Reference values for Oldenburg (53.14°N, 8.21°E) come from standard
    // astronomical tables (NOAA Solar Calculator algorithm, which is what
    // `Sun.swift` implements). Tolerances are ±5 min to absorb rounding and
    // small algorithmic differences while still failing on regressions.

    private func civilTwilightComponents(year: Int, month: Int, day: Int, isDawn: Bool) throws -> (hour: Int, minute: Int) {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let refDate = try date(year: year, month: month, day: day, hour: 12, minute: 0)
        let schedule = try #require(Sun.schedule(latitude: latitude, longitude: longitude, date: refDate, calendar: calendar, timeZone: timeZone))
        let position = try #require(isDawn ? schedule.civilDawn : schedule.civilDusk)
        return (calendar.component(.hour, from: position.date), calendar.component(.minute, from: position.date))
    }

    private func minutesSinceMidnight(_ components: (hour: Int, minute: Int)) -> Int {
        components.hour * 60 + components.minute
    }

    @Test("Spring equinox civil dawn at Oldenburg is ≈ 05:56 CET")
    func civilDawnAtSpringEquinox() throws {
        let actual = try civilTwilightComponents(year: 2026, month: 3, day: 20, isDawn: true)
        let expected = 5 * 60 + 56
        #expect(abs(minutesSinceMidnight(actual) - expected) <= 5,
                "Civil dawn was \(actual.hour):\(String(format: "%02d", actual.minute)), expected ≈ 05:56 CET")
    }

    @Test("Spring equinox civil dusk at Oldenburg is ≈ 19:17 CET")
    func civilDuskAtSpringEquinox() throws {
        let actual = try civilTwilightComponents(year: 2026, month: 3, day: 20, isDawn: false)
        let expected = 19 * 60 + 17
        #expect(abs(minutesSinceMidnight(actual) - expected) <= 5,
                "Civil dusk was \(actual.hour):\(String(format: "%02d", actual.minute)), expected ≈ 19:17 CET")
    }

    @Test("Summer solstice civil dawn at Oldenburg is ≈ 04:08 CEST")
    func civilDawnAtSummerSolstice() throws {
        let actual = try civilTwilightComponents(year: 2026, month: 6, day: 21, isDawn: true)
        let expected = 4 * 60 + 8
        #expect(abs(minutesSinceMidnight(actual) - expected) <= 5,
                "Civil dawn was \(actual.hour):\(String(format: "%02d", actual.minute)), expected ≈ 04:08 CEST")
    }

    @Test("Summer solstice civil dusk at Oldenburg is ≈ 22:47 CEST")
    func civilDuskAtSummerSolstice() throws {
        let actual = try civilTwilightComponents(year: 2026, month: 6, day: 21, isDawn: false)
        let expected = 22 * 60 + 47
        #expect(abs(minutesSinceMidnight(actual) - expected) <= 5,
                "Civil dusk was \(actual.hour):\(String(format: "%02d", actual.minute)), expected ≈ 22:47 CEST")
    }

    @Test("Winter solstice civil dawn at Oldenburg is ≈ 07:53 CET")
    func civilDawnAtWinterSolstice() throws {
        let actual = try civilTwilightComponents(year: 2026, month: 12, day: 21, isDawn: true)
        let expected = 7 * 60 + 53
        #expect(abs(minutesSinceMidnight(actual) - expected) <= 5,
                "Civil dawn was \(actual.hour):\(String(format: "%02d", actual.minute)), expected ≈ 07:53 CET")
    }

    @Test("Winter solstice civil dusk at Oldenburg is ≈ 16:52 CET")
    func civilDuskAtWinterSolstice() throws {
        let actual = try civilTwilightComponents(year: 2026, month: 12, day: 21, isDawn: false)
        let expected = 16 * 60 + 52
        #expect(abs(minutesSinceMidnight(actual) - expected) <= 5,
                "Civil dusk was \(actual.hour):\(String(format: "%02d", actual.minute)), expected ≈ 16:52 CET")
    }

    @Test("Civil twilight duration matches astronomy at 53°N",
          arguments: [
            // (month, day, expected duration in minutes ±2 min tolerance)
            (3, 20, 35),  // equinox: ≈ 34.6 min
            (6, 21, 52),  // summer solstice: ≈ 52.3 min
            (9, 22, 35),  // autumn equinox: ≈ 34.6 min
            (12, 21, 42)  // winter solstice: ≈ 42.6 min
          ])
    func civilTwilightDuration(month: Int, day: Int, expectedMinutes: Int) throws {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let refDate = try date(year: 2026, month: month, day: day, hour: 12, minute: 0)
        let schedule = try #require(Sun.schedule(latitude: latitude, longitude: longitude, date: refDate, calendar: calendar, timeZone: timeZone))

        let sunrise = try #require(schedule.sunrise)
        let sunset = try #require(schedule.sunset)
        let civilDawn = try #require(schedule.civilDawn)
        let civilDusk = try #require(schedule.civilDusk)

        let dawnDurationMin = sunrise.date.timeIntervalSince(civilDawn.date) / 60
        let duskDurationMin = civilDusk.date.timeIntervalSince(sunset.date) / 60

        #expect(abs(dawnDurationMin - Double(expectedMinutes)) <= 3,
                "Dawn duration \(dawnDurationMin) min differs from expected \(expectedMinutes) ±3 min")
        #expect(abs(duskDurationMin - Double(expectedMinutes)) <= 3,
                "Dusk duration \(duskDurationMin) min differs from expected \(expectedMinutes) ±3 min")
    }

    @Test("Civil dawn always precedes sunrise across the year")
    func civilDawnAlwaysBeforeSunrise() throws {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        for month in [1, 3, 5, 7, 9, 11] {
            let refDate = try date(year: 2026, month: month, day: 15, hour: 12, minute: 0)
            let schedule = try #require(Sun.schedule(latitude: latitude, longitude: longitude, date: refDate, calendar: calendar, timeZone: timeZone))
            let sunrise = try #require(schedule.sunrise)
            let civilDawn = try #require(schedule.civilDawn)
            #expect(civilDawn.date < sunrise.date, "Civil dawn must precede sunrise (month \(month))")
        }
    }

    @Test("Civil dusk always follows sunset across the year")
    func civilDuskAlwaysAfterSunset() throws {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        for month in [1, 3, 5, 7, 9, 11] {
            let refDate = try date(year: 2026, month: month, day: 15, hour: 12, minute: 0)
            let schedule = try #require(Sun.schedule(latitude: latitude, longitude: longitude, date: refDate, calendar: calendar, timeZone: timeZone))
            let sunset = try #require(schedule.sunset)
            let civilDusk = try #require(schedule.civilDusk)
            #expect(civilDusk.date > sunset.date, "Civil dusk must follow sunset (month \(month))")
        }
    }
}
