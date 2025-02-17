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

    /// Helper function to create a specific date
    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var dateComponents = DateComponents()
        dateComponents.year = year
        dateComponents.month = month
        dateComponents.day = day
        dateComponents.hour = hour
        dateComponents.minute = minute
        let calendar = Calendar.current
        return calendar.date(from: dateComponents)!
    }

    @Test("Test case for when the date is during the day (between sunrise and sunset)")
    func testCircadianPercentage_Daytime() {
        let date = self.date(year: 2023, month: 7, day: 25, hour: 12, minute: 0) // Solar noon

        let sunData = getSunData(for: date)
        let percentage = getNormalizedBrightnessValue(sunData: sunData, current: date.percentageOfDay())

        #expect(percentage > 0)
        #expect(percentage <= 1)
    }

    @Test("Test case for when the date is during the night (between sunset and sunrise)", .tags(.localOnly))
    func testCircadianPercentage_Nighttime() {
        let date = self.date(year: 2023, month: 7, day: 25, hour: 2, minute: 0) // During night

        let sunData = getSunData(for: date)
        let percentage = getNormalizedBrightnessValue(sunData: sunData, current: date.percentageOfDay())

        #expect(percentage > 0.2)
        #expect(percentage < 0.3)
    }

    @Test("Test case for when there's no sunrise or sunset (e.g., polar regions during certain seasons)")
    func testCircadianPercentage_NoSunriseSunset() {
        let date = self.date(year: 2023, month: 7, day: 25, hour: 12, minute: 0)

        let sunData = getSunData(for: date)
        let percentage = getNormalizedBrightnessValue(sunData: sunData, current: date.percentageOfDay())

        #expect(percentage == 1)
    }
}
