//
//  CircadianLightTests.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 25.07.24.
//

import Foundation
@testable import HAModels
import Testing

struct CircadianTests {

    /// Symmetric, easy-to-reason-about sun data:
    /// sunrise 06:00, solar noon 12:00, sunset 18:00.
    private static let standardSunData = SunData(sunrise: 0.25,
                                                 sunset: 0.75,
                                                 solarNoon: 0.5,
                                                 solarMidnight: 0.0)

    /// Short winter day: sunrise 08:00, sunset 16:15 — approximates Oldenburg
    /// on the shortest days of the year and is what previously produced the
    /// "still cool after sunset" bug.
    private static let winterSunData = SunData(sunrise: 8.0 / 24.0,
                                               sunset: 16.25 / 24.0,
                                               solarNoon: 12.125 / 24.0,
                                               solarMidnight: 0.00)

    private func fractionOfDay(hour: Double, minute: Double = 0) -> Double {
        (hour * 3600 + minute * 60) / 86_400
    }

    // MARK: - Brightness curve

    @Test("Brightness at solar noon is full")
    func brightnessAtSolarNoon() {
        let value = getNormalizedBrightnessValue(sunData: Self.standardSunData,
                                                 current: Self.standardSunData.solarNoon)
        #expect(value == 1)
    }

    @Test("Brightness at sunrise is the midpoint of the dawn ramp")
    func brightnessAtSunrise() {
        let value = getNormalizedBrightnessValue(sunData: Self.standardSunData,
                                                 current: Self.standardSunData.sunrise)
        #expect(abs(value - 0.5) < 0.001)
    }

    @Test("Brightness at sunset is the midpoint of the dusk ramp")
    func brightnessAtSunset() {
        let value = getNormalizedBrightnessValue(sunData: Self.standardSunData,
                                                 current: Self.standardSunData.sunset)
        #expect(abs(value - 0.5) < 0.001)
    }

    @Test("Brightness deep in the night is zero")
    func brightnessAtNight() {
        let atTwoAM = getNormalizedBrightnessValue(sunData: Self.standardSunData,
                                                   current: fractionOfDay(hour: 2))
        let atMidnight = getNormalizedBrightnessValue(sunData: Self.standardSunData,
                                                     current: 0)
        #expect(atTwoAM == 0)
        #expect(atMidnight == 0)
    }

    @Test("Brightness stays at zero after a winter sunset")
    func brightnessAfterWinterSunset() {
        // 18:00 on a short December day is well past sunset → must be 0.
        let value = getNormalizedBrightnessValue(sunData: Self.winterSunData,
                                                 current: fractionOfDay(hour: 18))
        #expect(value == 0)
    }

    @Test("Brightness ramp is monotone non-decreasing across dawn")
    func brightnessMonotoneAcrossDawn() {
        let sun = Self.standardSunData
        let step = 0.002
        var current = sun.sunrise - 0.05
        var previous = getNormalizedBrightnessValue(sunData: sun, current: current)
        while current <= sun.sunrise + 0.05 {
            let next = getNormalizedBrightnessValue(sunData: sun, current: current)
            #expect(next >= previous - 0.001)
            previous = next
            current += step
        }
    }

    // MARK: - Color temperature curve

    @Test("Color temperature peaks (cool) at solar noon")
    func colorTemperatureAtSolarNoon() {
        let value = getNormalizedColorTemperatureValue(sunData: Self.standardSunData,
                                                       current: Self.standardSunData.solarNoon)
        #expect(abs(value - 1.0) < 0.001)
    }

    @Test("Color temperature is warm at and before sunrise")
    func colorTemperatureBeforeSunrise() {
        let atSunrise = getNormalizedColorTemperatureValue(sunData: Self.standardSunData,
                                                           current: Self.standardSunData.sunrise)
        let atThreeAM = getNormalizedColorTemperatureValue(sunData: Self.standardSunData,
                                                           current: 3.0 / 24.0)
        #expect(atSunrise == 0)
        #expect(atThreeAM == 0)
    }

    @Test("Color temperature is warm at and after sunset")
    func colorTemperatureAfterSunset() {
        let atSunset = getNormalizedColorTemperatureValue(sunData: Self.standardSunData,
                                                          current: Self.standardSunData.sunset)
        let atEvening = getNormalizedColorTemperatureValue(sunData: Self.standardSunData,
                                                          current: 21.0 / 24.0)
        #expect(atSunset == 0)
        #expect(atEvening == 0)
    }

    /// Regression guard for the previous implementation which computed color
    /// temperature purely from solar noon. On a short winter day the old
    /// formula still reported ≈ 0.39 at 17:00 (well past a 16:15 sunset).
    @Test("Color temperature drops to warm immediately after a winter sunset")
    func colorTemperatureWinterEveningIsWarm() {
        let sun = Self.winterSunData
        let justAfterSunset = getNormalizedColorTemperatureValue(sunData: sun,
                                                                 current: fractionOfDay(hour: 17))
        #expect(justAfterSunset == 0)
    }

    @Test("Color temperature increases monotonically from sunrise to solar noon")
    func colorTemperatureMorningRampIsMonotone() {
        let sun = Self.standardSunData
        let step = 0.005
        var current = sun.sunrise
        var previous = getNormalizedColorTemperatureValue(sunData: sun, current: current)
        while current <= sun.solarNoon {
            let next = getNormalizedColorTemperatureValue(sunData: sun, current: current)
            #expect(next >= previous - 0.001)
            previous = next
            current += step
        }
    }

    @Test("Color temperature decreases monotonically from solar noon to sunset")
    func colorTemperatureAfternoonRampIsMonotone() {
        let sun = Self.standardSunData
        let step = 0.005
        var current = sun.solarNoon
        var previous = getNormalizedColorTemperatureValue(sunData: sun, current: current)
        while current <= sun.sunset {
            let next = getNormalizedColorTemperatureValue(sunData: sun, current: current)
            #expect(next <= previous + 0.001)
            previous = next
            current += step
        }
    }

    @Test("Color temperature at the midpoint of the morning ramp is 0.5")
    func colorTemperatureMorningMidpoint() {
        let sun = Self.standardSunData
        let midpoint = (sun.sunrise + sun.solarNoon) / 2
        let value = getNormalizedColorTemperatureValue(sunData: sun, current: midpoint)
        #expect(abs(value - 0.5) < 0.001)
    }

    // MARK: - Real-date smoke tests

    @Test("Values stay within 0…1 across a full day")
    func valuesRemainNormalizedAllDay() {
        let sun = Self.standardSunData
        for minute in stride(from: 0, through: 24 * 60, by: 15) {
            let current = Double(minute) / (24.0 * 60)
            let brightness = getNormalizedBrightnessValue(sunData: sun, current: current)
            let colorTemp = getNormalizedColorTemperatureValue(sunData: sun, current: current)
            #expect((0...1).contains(brightness))
            #expect((0...1).contains(colorTemp))
        }
    }

    @Test("Midsummer midday stays at full brightness", .tags(.localOnly))
    func testCircadianPercentage_Daytime() throws {
        // setenv so the absolute `percentageOfDay()` resolves to local noon.
        setenv("TZ", "Europe/Berlin", 1)
        CFTimeZoneResetSystem()

        var components = DateComponents()
        components.year = 2023
        components.month = 7
        components.day = 25
        components.hour = 12
        let date = try #require(Calendar.current.date(from: components))

        let sunData = getSunData(for: date)
        let percentage = getNormalizedBrightnessValue(sunData: sunData, current: date.percentageOfDay())
        #expect(percentage == 1)
    }

    @Test("Night-time brightness is zero (no dawn ramp bleed into the night)", .tags(.localOnly))
    func testCircadianPercentage_Nighttime() throws {
        setenv("TZ", "Europe/Berlin", 1)
        CFTimeZoneResetSystem()

        var components = DateComponents()
        components.year = 2023
        components.month = 7
        components.day = 25
        components.hour = 2
        let date = try #require(Calendar.current.date(from: components))

        let sunData = getSunData(for: date)
        let percentage = getNormalizedBrightnessValue(sunData: sunData, current: date.percentageOfDay())

        // Previously this returned ≈ 0.12 because the sine ramp started at
        // midnight; the dawn window is now anchored tightly around sunrise,
        // so 02:00 is firmly "night" and must report 0.
        #expect(percentage == 0)
    }
}
