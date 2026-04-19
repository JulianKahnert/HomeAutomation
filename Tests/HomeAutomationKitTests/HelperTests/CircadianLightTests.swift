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

    /// Symmetric, easy-to-reason-about sun data: nautical dawn 04:42, sunrise
    /// 06:00, solar noon 12:00, sunset 18:00, nautical dusk 19:18. Nautical
    /// twilight is ≈ 78 min wide (matching mid-latitudes around the equinox).
    private static let standardSunData = SunData(sunrise: 0.25,
                                                 sunset: 0.75,
                                                 solarNoon: 0.5,
                                                 solarMidnight: 0.0,
                                                 nauticalDawn: 0.196,
                                                 nauticalDusk: 0.804)

    /// Short winter day at Oldenburg: sunrise 08:00, sunset 16:15,
    /// nautical twilight ≈ 88 min on either side.
    private static let winterSunData = SunData(sunrise: 8.0 / 24.0,
                                               sunset: 16.25 / 24.0,
                                               solarNoon: 12.125 / 24.0,
                                               solarMidnight: 0.00,
                                               nauticalDawn: (8.0 - 88.0 / 60.0) / 24.0,
                                               nauticalDusk: (16.25 + 88.0 / 60.0) / 24.0)

    /// Sun data without nautical twilight info — exercises the constant
    /// fallback ramp used near the summer solstice when nautical dusk wraps
    /// past midnight.
    private static let sunDataWithoutTwilight = SunData(sunrise: 0.25,
                                                        sunset: 0.75,
                                                        solarNoon: 0.5,
                                                        solarMidnight: 0.0)

    private func fractionOfDay(hour: Double, minute: Double = 0) -> Double {
        (hour * 3600 + minute * 60) / 86_400
    }

    // MARK: - Brightness curve (nautical-twilight-anchored)

    @Test("Brightness at solar noon is full")
    func brightnessAtSolarNoon() {
        let value = getNormalizedBrightnessValue(sunData: Self.standardSunData,
                                                 current: Self.standardSunData.solarNoon)
        #expect(value == 1)
    }

    @Test("Brightness at sunrise is 0.5 (midpoint of the dawn ramp)")
    func brightnessAtSunrise() {
        // Cosine ramp is centred on sunrise, so the inflection point sits
        // exactly there: lights are halfway between dark and full daylight.
        let value = getNormalizedBrightnessValue(sunData: Self.standardSunData,
                                                 current: Self.standardSunData.sunrise)
        #expect(abs(value - 0.5) < 0.001)
    }

    @Test("Brightness at sunset is 0.5 (midpoint of the dusk ramp)")
    func brightnessAtSunset() {
        let value = getNormalizedBrightnessValue(sunData: Self.standardSunData,
                                                 current: Self.standardSunData.sunset)
        #expect(abs(value - 0.5) < 0.001)
    }

    @Test("Brightness at nautical dawn is zero (start of dawn ramp)")
    func brightnessAtNauticalDawn() throws {
        let nauticalDawn = try #require(Self.standardSunData.nauticalDawn)
        let value = getNormalizedBrightnessValue(sunData: Self.standardSunData, current: nauticalDawn)
        #expect(abs(value - 0.0) < 0.001)
    }

    @Test("Brightness at nautical dusk is zero (end of dusk ramp)")
    func brightnessAtNauticalDusk() throws {
        let nauticalDusk = try #require(Self.standardSunData.nauticalDusk)
        let value = getNormalizedBrightnessValue(sunData: Self.standardSunData, current: nauticalDusk)
        #expect(abs(value - 0.0) < 0.001)
    }

    @Test("Brightness reaches 1 one nautical-twilight after sunrise")
    func brightnessAtPeakStart() throws {
        let sun = Self.standardSunData
        let nauticalDawn = try #require(sun.nauticalDawn)
        let peakStart = sun.sunrise + (sun.sunrise - nauticalDawn)
        let value = getNormalizedBrightnessValue(sunData: sun, current: peakStart)
        #expect(abs(value - 1.0) < 0.001)
    }

    @Test("Brightness leaves 1 one nautical-twilight before sunset")
    func brightnessAtPeakEnd() throws {
        let sun = Self.standardSunData
        let nauticalDusk = try #require(sun.nauticalDusk)
        let peakEnd = sun.sunset - (nauticalDusk - sun.sunset)
        let value = getNormalizedBrightnessValue(sunData: sun, current: peakEnd)
        #expect(abs(value - 1.0) < 0.001)
    }

    @Test("Brightness is already dimming two minutes before sunset")
    func brightnessJustBeforeSunset() {
        // Real-world scenario: sunset 20:32, nautical dusk ≈ 78 min later
        // (mid-April at 53°N). At 20:30 (two minutes before sunset) the
        // dusk-ramp midpoint sits at sunset, so brightness must be a touch
        // above 0.5 — well below 1.
        let sunsetFraction = (20.0 + 32.0 / 60.0) / 24.0
        let nautDuskFraction = sunsetFraction + (78.0 / 60.0) / 24.0
        let nautDawnFraction = (5.0 + 8.0 / 60.0) / 24.0
        let sunriseFraction = (6.0 + 26.0 / 60.0) / 24.0
        let sun = SunData(sunrise: sunriseFraction,
                          sunset: sunsetFraction,
                          solarNoon: 13.5 / 24.0,
                          solarMidnight: 1.5 / 24.0,
                          nauticalDawn: nautDawnFraction,
                          nauticalDusk: nautDuskFraction)
        let twoMinutesBeforeSunset = (20.0 + 30.0 / 60.0) / 24.0
        let value = getNormalizedBrightnessValue(sunData: sun, current: twoMinutesBeforeSunset)
        #expect(value > 0.45 && value < 0.6,
                "Expected ≈ 0.5 just before sunset, got \(value)")
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
        // 18:00 on a short December day is well past nautical dusk (≈ 17:43) → 0.
        let value = getNormalizedBrightnessValue(sunData: Self.winterSunData,
                                                 current: fractionOfDay(hour: 18))
        #expect(value == 0)
    }

    @Test("Brightness ramp is monotone non-decreasing across the entire dawn ramp")
    func brightnessMonotoneAcrossDawn() throws {
        let sun = Self.standardSunData
        let nauticalDawn = try #require(sun.nauticalDawn)
        let rampHalf = sun.sunrise - nauticalDawn
        let step = 0.002
        var current = nauticalDawn - 0.01
        var previous = getNormalizedBrightnessValue(sunData: sun, current: current)
        while current <= sun.sunrise + rampHalf + 0.01 {
            let next = getNormalizedBrightnessValue(sunData: sun, current: current)
            #expect(next >= previous - 0.001)
            previous = next
            current += step
        }
    }

    @Test("Brightness ramp is monotone non-increasing across the entire dusk ramp")
    func brightnessMonotoneAcrossDusk() throws {
        let sun = Self.standardSunData
        let nauticalDusk = try #require(sun.nauticalDusk)
        let rampHalf = nauticalDusk - sun.sunset
        let step = 0.002
        var current = sun.sunset - rampHalf - 0.01
        var previous = getNormalizedBrightnessValue(sunData: sun, current: current)
        while current <= nauticalDusk + 0.01 {
            let next = getNormalizedBrightnessValue(sunData: sun, current: current)
            #expect(next <= previous + 0.001)
            previous = next
            current += step
        }
    }

    // MARK: - Brightness curve fallback

    @Test("Constant fallback: brightness still reaches 1 at noon and 0 at night")
    func brightnessConstantFallback() {
        let sun = Self.sunDataWithoutTwilight
        let atNoon = getNormalizedBrightnessValue(sunData: sun, current: sun.solarNoon)
        let atMidnight = getNormalizedBrightnessValue(sunData: sun, current: 0)
        #expect(atNoon == 1)
        #expect(atMidnight == 0)
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

    /// Asserts that 45 minutes past a winter sunset the curve has already
    /// dropped to fully warm — color temperature must follow the actual
    /// daylight window, not just the symmetry around solar noon.
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

        // 02:00 sits well before the dawn ramp window, so the curve must
        // report `0` — the configured night-floor in callers takes over.
        #expect(percentage == 0)
    }
}
