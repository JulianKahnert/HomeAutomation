//
//  CircadianLight.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 25.07.24.
//

import Foundation

/// Half-width (as a fraction of a day) of the dawn/dusk ramp used as a
/// fallback when nautical twilight is not available — typically near the
/// summer solstice at mid-latitudes when nautical dusk wraps past midnight.
/// ~43 min, roughly the civil-twilight duration at 53°N around the equinox.
private let fallbackRampHalfWidth: Double = 0.03

/// Returns the circadian brightness target (`0…1`) for the given moment.
///
/// The cosine ease-in-out ramps are centred on `sunrise` and `sunset` with
/// a half-width derived from nautical twilight (sun 12° below horizon),
/// giving a ~75 min "golden-hour" easing on either side of the horizon
/// crossing at mid-latitudes around the equinox. Brightness already drops
/// before sunset and only reaches `0` at nautical dusk; perceived daylight
/// is matched more closely than with sunrise/sunset as the ramp endpoints.
///
/// `sunrise` and `sunset` sit at the `0.5` point of their respective ramps;
/// nautical dawn/dusk sit at `0`. The full-brightness plateau spans from one
/// nautical-twilight duration after sunrise to the same duration before
/// sunset.
///
/// When nautical twilight is not provided — high latitudes near the summer
/// solstice where the sun never dips 12° below the horizon, or sun data
/// constructed by hand without it — the curve falls back to a fixed
/// ``fallbackRampHalfWidth`` around sunrise/sunset.
///
/// Polar regions without a sunrise/sunset return `0` because `sunData` is
/// `nil`; callers such as ``MotionAtNight`` clamp this to a configured floor.
public func getNormalizedBrightnessValue(sunData: SunData? = nil, current: Double? = nil) -> Float {
    guard let sunData = sunData ?? getSunData() else { return 0 }
    let current = current ?? Date().percentageOfDay()

    let dawnHalf: Double
    let duskHalf: Double
    if let nautDawn = sunData.nauticalDawn, let nautDusk = sunData.nauticalDusk {
        dawnHalf = max(0, sunData.sunrise - nautDawn)
        duskHalf = max(0, nautDusk - sunData.sunset)
    } else {
        dawnHalf = fallbackRampHalfWidth
        duskHalf = fallbackRampHalfWidth
    }

    let dawnStart = sunData.sunrise - dawnHalf
    let dawnEnd = sunData.sunrise + dawnHalf
    let duskStart = sunData.sunset - duskHalf
    let duskEnd = sunData.sunset + duskHalf

    let value: Double
    if current <= dawnStart || current >= duskEnd {
        value = 0
    } else if current >= dawnEnd && current <= duskStart {
        value = 1
    } else if current < dawnEnd, dawnEnd > dawnStart {
        let progress = (current - dawnStart) / (dawnEnd - dawnStart)
        value = (1 - cos(.pi * progress)) / 2
    } else if duskEnd > duskStart {
        let progress = (current - duskStart) / (duskEnd - duskStart)
        value = (1 + cos(.pi * progress)) / 2
    } else {
        // Degenerate ramp window (zero width) — fall through to bright.
        value = 1
    }

    return Float(value.clamped(to: 0...1))
}

/// Returns the circadian color-temperature target (`0` = warmest, `1` = coolest)
/// for the given moment.
///
/// The curve is anchored to the sun: warm before `sunrise` and after `sunset`,
/// smoothly ramping up from `sunrise` to the coolest point at `solarNoon`, and
/// back down to warm at `sunset`. Anchoring to `sunrise`/`sunset` (and not
/// only `solarNoon`) keeps short winter evenings warm immediately after sunset
/// instead of staying cool well into the night.
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

    let sunriseFraction = sunrise.date.percentageOfDay()
    let sunsetFraction = sunset.date.percentageOfDay()

    // Nautical twilight times computed by `Sun.schedule` can wrap past midnight
    // at mid-latitudes around the summer solstice (the sun barely dips 12°
    // below the horizon, so dusk lands early next morning and gets reported
    // as a small fraction-of-day value). Discard those wrap-arounds so the
    // brightness curve falls back to the constant ramp width.
    let nauticalDawnFraction = today.nauticalDawn?.date.percentageOfDay()
    let nauticalDuskFraction = today.nauticalDusk?.date.percentageOfDay()

    return SunData(sunrise: sunriseFraction,
                   sunset: sunsetFraction,
                   solarNoon: today.solarNoon.date.percentageOfDay(),
                   solarMidnight: today.solarMidnight.date.percentageOfDay(),
                   nauticalDawn: nauticalDawnFraction.flatMap { $0 < sunriseFraction ? $0 : nil },
                   nauticalDusk: nauticalDuskFraction.flatMap { $0 > sunsetFraction ? $0 : nil })
}

/// Data for the sun
///
/// All parameters are normalized to the current day with values between 0 and 1.
/// E.g. sunrise = 0.25 means that the sun rises at 6:00 am.
public struct SunData: Sendable {
    public init(sunrise: Double,
                sunset: Double,
                solarNoon: Double,
                solarMidnight: Double,
                nauticalDawn: Double? = nil,
                nauticalDusk: Double? = nil) {
        for value in [sunrise, sunset, solarNoon, solarMidnight] {
            assert((0...1).contains(value), "Wrong value for sun data: \(value)")
        }
        for value in [nauticalDawn, nauticalDusk].compactMap({ $0 }) {
            assert((0...1).contains(value), "Wrong twilight value for sun data: \(value)")
        }
        self.sunrise = sunrise.clamped(to: 0...1)
        self.sunset = sunset.clamped(to: 0...1)
        self.solarNoon = solarNoon.clamped(to: 0...1)
        self.solarMidnight = solarMidnight.clamped(to: 0...1)
        self.nauticalDawn = nauticalDawn?.clamped(to: 0...1)
        self.nauticalDusk = nauticalDusk?.clamped(to: 0...1)
    }

    public let sunrise: Double
    public let sunset: Double
    public let solarNoon: Double
    public let solarMidnight: Double

    /// Nautical dawn (sun 12° below the horizon, ascending). Optional — at
    /// mid-latitudes around the summer solstice the sun never dips this far,
    /// or its dawn/dusk crossings wrap past midnight.
    public let nauticalDawn: Double?

    /// Nautical dusk (sun 12° below the horizon, descending). Same caveat as ``nauticalDawn``.
    public let nauticalDusk: Double?
}
