//
//  CircadianLightView.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 03.11.24.
//

#if DEBUG
import Charts
import HAModels
import SwiftUI

public struct CircadianLightView: View {
    let latitude = 53.14194
    let longitude = 8.21292
    let sunData: SunData

    public init(sunData: SunData) {
        self.sunData = sunData
    }

    public init(date: Date) {
        self.sunData = getSunData(for: date)!
    }

    public var body: some View {
        Chart {
            LinePlot(x: "hour", y: "value", domain: 0...23, function: { rawHour in
                return Double(getNormalizedBrightnessValue(sunData: sunData, current: rawHour / 24))
            })
            .foregroundStyle(.blue)

            LinePlot(x: "hour", y: "value", domain: 0...23, function: { rawHour in
                return Double(getNormalizedColorTemperatureValue(sunData: sunData, current: rawHour / 24))
            })
            .foregroundStyle(.orange)

            RuleMark(x: .value("Sunrise", sunData.sunrise * 24))
                .foregroundStyle(.red)
            RuleMark(x: .value("Sunset", sunData.sunset * 24))
                .foregroundStyle(.red)

            RuleMark(x: .value("Solar Noon", sunData.solarNoon * 24))
                .foregroundStyle(.yellow)
            RuleMark(x: .value("Solar Midnight", sunData.solarMidnight * 24))
                .foregroundStyle(.yellow)
        }
        .chartXScale(domain: 0...23)
        .chartYScale(domain: 0...1)
    }
}

// swiftlint:disable:next force_try
#Preview("Date View", traits: .fixedLayout(width: 500, height: 1200)) {
    // swiftlint:disable force_try
    CircadianLightView(date: try! Date("2025-01-01T12:00:00+02:00", strategy: .iso8601))
    CircadianLightView(date: try! Date("2025-03-01T12:00:00+02:00", strategy: .iso8601))
    CircadianLightView(date: try! Date("2025-06-01T12:00:00+02:00", strategy: .iso8601))
    CircadianLightView(date: try! Date("2025-09-01T12:00:00+02:00", strategy: .iso8601))
    CircadianLightView(date: try! Date("2025-12-01T12:00:00+02:00", strategy: .iso8601))
    // swiftlint:enable force_try
}

#Preview("Symmetric View", traits: .fixedLayout(width: 500, height: 300)) {
    CircadianLightView(sunData: SunData(sunrise: 0.25,
                                        sunset: 0.75,
                                        solarNoon: 0.5,
                                        solarMidnight: 0.0))
}

#Preview("Realistic View", traits: .fixedLayout(width: 500, height: 300)) {
    CircadianLightView(sunData: SunData(sunrise: 0.31,
                                        sunset: 0.7,
                                        solarNoon: 0.5,
                                        solarMidnight: 0.01))
}

#endif
