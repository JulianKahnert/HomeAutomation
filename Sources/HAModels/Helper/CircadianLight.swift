//
//  CircadianLight.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 25.07.24.
//

import Foundation

/// Half-width of the sunrise/sunset cosine ramp, expressed as a fraction of a day.
/// `0.03 ≈ 43 minutes`, which approximates civil twilight at the configured latitude
/// and keeps the full-brightness window aligned with the actual daylight hours.
private let dayRampHalfWidth: Double = 0.03

/// Returns the circadian brightness target (`0…1`) for the given moment.
///
/// The curve holds at `0` during the night, ramps up smoothly across civil
/// dawn, stays at `1` while the sun is above the horizon, and ramps down
/// across civil dusk. Anchoring the ramps to `sunrise`/`sunset` (instead of
/// letting a nearly 2 h window bleed into the middle of the night, as the
/// previous implementation did) prevents the motion-at-night automation from
/// picking a substantially brighter target at 2 a.m. than at 4 a.m.
///
/// Polar regions without a sunrise/sunset return `0` because `sunData` is
/// `nil`; callers such as ``MotionAtNight`` clamp this to a configured floor.
public func getNormalizedBrightnessValue(sunData: SunData? = nil, current: Double? = nil) -> Float {
    guard let sunData = sunData ?? getSunData() else { return 0 }
    let current = current ?? Date().percentageOfDay()

    let dawnStart = sunData.sunrise - dayRampHalfWidth
    let dawnEnd = sunData.sunrise + dayRampHalfWidth
    let duskStart = sunData.sunset - dayRampHalfWidth
    let duskEnd = sunData.sunset + dayRampHalfWidth

    let value: Double
    if current <= dawnStart || current >= duskEnd {
        value = 0
    } else if current >= dawnEnd && current <= duskStart {
        value = 1
    } else if current < dawnEnd {
        let progress = (current - dawnStart) / (dawnEnd - dawnStart)
        value = (1 - cos(.pi * progress)) / 2
    } else {
        let progress = (current - duskStart) / (duskEnd - duskStart)
        value = (1 + cos(.pi * progress)) / 2
    }

    return Float(value.clamped(to: 0...1))
}

/// Returns the circadian color-temperature target (`0` = warmest, `1` = coolest)
/// for the given moment.
///
/// The curve is anchored to the sun: warm before sunrise and after sunset
/// (so lights do not stay cool well into a winter evening), smoothly ramping
/// up from `sunrise` to the coolest point at `solarNoon`, and back down to
/// warm at `sunset`. The previous implementation was symmetric around
/// `solarNoon` only and ignored `sunrise`/`sunset`, producing cool light at
/// 17:00 on a December evening and warm light at 04:00 in midsummer despite
/// the sun already being up.
public func getNormalizedColorTemperatureValue(sunData: SunData? = nil, current: Double? = nil) -> Float {
    guard let sunData = sunData ?? getSunData() else { return 0 }
    let current = current ?? Date().percentageOfDay()

    let morningSpan = sunData.solarNoon - sunData.sunrise
    let afternoonSpan = sunData.sunset - sunData.solarNoon

    let value: Double
    if current <= sunData.sunrise || current >= sunData.sunset {
        value = 0
    } else if current < sunData.solarNoon, morningSpan > 0 {
        let progress = (current - sunData.sunrise) / morningSpan
        value = (1 - cos(.pi * progress)) / 2
    } else if afternoonSpan > 0 {
        let progress = (current - sunData.solarNoon) / afternoonSpan
        value = (1 + cos(.pi * progress)) / 2
    } else {
        // Degenerate sun data (sunrise == solarNoon or solarNoon == sunset).
        // Return the neutral warm value rather than dividing by zero.
        value = 0
    }

    return Float(value.clamped(to: 0...1))
}

public func getSunData(for date: Date = Date()) -> SunData? {
    guard let today = Sun.schedule(latitude: 53.14194, longitude: 8.21292, date: date),
          let sunrise = today.sunrise,
          let sunset = today.sunset else {
        assertionFailure("Could not get the sun data.")
        return nil
    }

    return SunData(sunrise: sunrise.date.percentageOfDay(),
                   sunset: sunset.date.percentageOfDay(),
                   solarNoon: today.solarNoon.date.percentageOfDay(),
                   solarMidnight: today.solarMidnight.date.percentageOfDay())
}

/// Data for the sun
///
/// All parameters are normalized to the current day with values between 0 and 1.
/// E.g. sunrise = 0.25 means that the sun rises at 6:00 am.
public struct SunData: Sendable {
    public init(sunrise: Double, sunset: Double, solarNoon: Double, solarMidnight: Double) {
        for value in [sunrise, sunset, solarNoon, solarMidnight] {
            assert((0...1).contains(value), "Wrong value for sun data: \(value)")
        }
        self.sunrise = sunrise.clamped(to: 0...1)
        self.sunset = sunset.clamped(to: 0...1)
        self.solarNoon = solarNoon.clamped(to: 0...1)
        self.solarMidnight = solarMidnight.clamped(to: 0...1)
    }

    public let sunrise: Double
    public let sunset: Double
    public let solarNoon: Double
    public let solarMidnight: Double
}
