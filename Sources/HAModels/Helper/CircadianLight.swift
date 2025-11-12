//
//  CircadianLight.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 25.07.24.
//

// swiftlint:disable identifier_name

import Foundation

public func getNormalizedBrightnessValue(sunData: SunData? = nil, current: Double? = nil) -> Float {
    guard let sunData = sunData ?? getSunData() else { return 0 }
    let current = current ?? Date().percentageOfDay()

    let adjustment = 0.1

    let value: Double
    if (sunData.sunrise + adjustment...sunData.sunset - adjustment).contains(current) {
        value = 1
    } else if current < sunData.sunrise + adjustment {
        value = sin(1 / (sunData.sunrise + adjustment) * .pi * current - (0.5 * .pi)) / 2 + 0.5
    } else {

        let a = 1 / (1 - sunData.sunset + adjustment)
        value = cos(a * .pi * (current - sunData.sunset + adjustment)) / 2 + 0.5
    }

    return Float(value)
}

public func getNormalizedColorTemperatureValue(sunData: SunData? = nil, current: Double? = nil) -> Float {
    guard let sunData = sunData ?? getSunData() else { return 0 }
    let current = current ?? Date().percentageOfDay()

    let steepness: Double = 1.3
    let x = steepness * (current - sunData.solarNoon + 0.5 / steepness)
    let value = -1 * cos(2 * .pi * x.clamped(to: 0...1)) / 2 + 0.5

    return Float(value)
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
