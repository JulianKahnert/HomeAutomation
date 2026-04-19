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

    // MARK: - Nautical twilight (sun at zenith 102°, i.e. 12° below the horizon)
    //
    // Reference values for Oldenburg (53.14°N, 8.21°E) come from standard
    // astronomical tables (NOAA Solar Calculator algorithm, which is what
    // `Sun.swift` implements). Tolerances are ±5 min to absorb rounding and
    // small algorithmic differences while still failing on regressions.
    // Nautical twilight is undefined at mid-latitudes around the summer
    // solstice — the sun never dips 12° below the horizon there.

    private func minutesSinceMidnight(_ components: (hour: Int, minute: Int)) -> Int {
        components.hour * 60 + components.minute
    }

    private func nauticalTwilightComponents(year: Int, month: Int, day: Int, isDawn: Bool) throws -> (hour: Int, minute: Int) {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let refDate = try date(year: year, month: month, day: day, hour: 12, minute: 0)
        let schedule = try #require(Sun.schedule(latitude: latitude, longitude: longitude, date: refDate, calendar: calendar, timeZone: timeZone))
        let position = try #require(isDawn ? schedule.nauticalDawn : schedule.nauticalDusk)
        return (calendar.component(.hour, from: position.date), calendar.component(.minute, from: position.date))
    }

    @Test("Spring equinox nautical dawn at Oldenburg is ≈ 05:14 CET")
    func nauticalDawnAtSpringEquinox() throws {
        let actual = try nauticalTwilightComponents(year: 2026, month: 3, day: 20, isDawn: true)
        let expected = 5 * 60 + 14
        #expect(abs(minutesSinceMidnight(actual) - expected) <= 5,
                "Nautical dawn was \(actual.hour):\(String(format: "%02d", actual.minute)), expected ≈ 05:14 CET")
    }

    @Test("Spring equinox nautical dusk at Oldenburg is ≈ 19:59 CET")
    func nauticalDuskAtSpringEquinox() throws {
        let actual = try nauticalTwilightComponents(year: 2026, month: 3, day: 20, isDawn: false)
        let expected = 19 * 60 + 59
        #expect(abs(minutesSinceMidnight(actual) - expected) <= 5,
                "Nautical dusk was \(actual.hour):\(String(format: "%02d", actual.minute)), expected ≈ 19:59 CET")
    }

    @Test("Winter solstice nautical dawn at Oldenburg is ≈ 07:06 CET")
    func nauticalDawnAtWinterSolstice() throws {
        let actual = try nauticalTwilightComponents(year: 2026, month: 12, day: 21, isDawn: true)
        let expected = 7 * 60 + 6
        #expect(abs(minutesSinceMidnight(actual) - expected) <= 5,
                "Nautical dawn was \(actual.hour):\(String(format: "%02d", actual.minute)), expected ≈ 07:06 CET")
    }

    @Test("Winter solstice nautical dusk at Oldenburg is ≈ 17:39 CET")
    func nauticalDuskAtWinterSolstice() throws {
        let actual = try nauticalTwilightComponents(year: 2026, month: 12, day: 21, isDawn: false)
        let expected = 17 * 60 + 39
        #expect(abs(minutesSinceMidnight(actual) - expected) <= 5,
                "Nautical dusk was \(actual.hour):\(String(format: "%02d", actual.minute)), expected ≈ 17:39 CET")
    }

    @Test("Nautical twilight duration matches astronomy at 53°N",
          arguments: [
            // (month, day, expected duration in minutes ±3 min tolerance)
            (3, 20, 76),  // equinox: ≈ 75.7 min
            (12, 21, 88)  // winter solstice: ≈ 87.9 min
          ])
    func nauticalTwilightDuration(month: Int, day: Int, expectedMinutes: Int) throws {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let refDate = try date(year: 2026, month: month, day: day, hour: 12, minute: 0)
        let schedule = try #require(Sun.schedule(latitude: latitude, longitude: longitude, date: refDate, calendar: calendar, timeZone: timeZone))

        let sunrise = try #require(schedule.sunrise)
        let sunset = try #require(schedule.sunset)
        let nauticalDawn = try #require(schedule.nauticalDawn)
        let nauticalDusk = try #require(schedule.nauticalDusk)

        let dawnDurationMin = sunrise.date.timeIntervalSince(nauticalDawn.date) / 60
        let duskDurationMin = nauticalDusk.date.timeIntervalSince(sunset.date) / 60

        #expect(abs(dawnDurationMin - Double(expectedMinutes)) <= 3,
                "Dawn duration \(dawnDurationMin) min differs from expected \(expectedMinutes) ±3 min")
        #expect(abs(duskDurationMin - Double(expectedMinutes)) <= 3,
                "Dusk duration \(duskDurationMin) min differs from expected \(expectedMinutes) ±3 min")
    }

    /// At 53°N the sun reaches a minimum elevation of about −13.5° around the
    /// summer solstice — only just below the −12° nautical-twilight threshold.
    /// `Sun.schedule` therefore reports a "dusk" time wrapped past midnight.
    /// `getSunData(for:)` is responsible for filtering those wrap-arounds out
    /// so the brightness curve falls back to civil twilight.
    @Test("Summer solstice: nautical dusk wrap is rejected by getSunData")
    func nauticalDuskWrapAtSummerSolsticeIsFiltered() throws {
        let summerDate = try date(year: 2026, month: 6, day: 21, hour: 12, minute: 0)
        let sunData = try #require(getSunData(for: summerDate))

        // Either nil (filtered) or — in the unlikely case the algorithm
        // returns it on the right side of midnight — strictly after sunset.
        if let nauticalDusk = sunData.nauticalDusk {
            #expect(nauticalDusk > sunData.sunset, "Nautical dusk \(nauticalDusk) must be after sunset \(sunData.sunset)")
        }
        if let nauticalDawn = sunData.nauticalDawn {
            #expect(nauticalDawn < sunData.sunrise, "Nautical dawn \(nauticalDawn) must be before sunrise \(sunData.sunrise)")
        }
    }
}
