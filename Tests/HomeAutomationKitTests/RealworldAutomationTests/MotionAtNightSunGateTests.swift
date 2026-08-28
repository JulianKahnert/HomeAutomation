//
//  MotionAtNightSunGateTests.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 28.08.26.
//

import Foundation
@testable import HAImplementations
@testable import HAModels
import Testing

struct MotionAtNightSunGateTests {
    // Oldenburg, Germany
    private let location = Location(latitude: 53.14194, longitude: 8.21292)

    private let deviceEveMotion = EveMotion(query: .init(placeId: "room1", name: "motion1"))
    private let deviceLightBulb = GenericSwitch(query: .init(placeId: "room1", name: "switch1"))
    private let deviceWindowContact = WindowContactSensor(query: .init(placeId: "room1", name: "contact1"))

    private var automation: MotionAtNight {
        MotionAtNight("motion-at-night",
                      motionSensors: [deviceEveMotion],
                      lightSensor: deviceEveMotion,
                      lights: [deviceLightBulb],
                      windowContacts: [deviceWindowContact],
                      minBrightness: 0.1)
    }

    // Winter date where sunrise (~08:30) and sunset (~16:40) both land on the same calendar day
    // under either UTC (CI) or Europe/Berlin (local) — see Sun.isSunBelowHorizon.
    private func date(hour: Int, minute: Int) throws -> Date {
        try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 15, hour: hour, minute: minute)))
    }

    @Test("Sun above horizon: window contacts are not respected")
    func windowContactsIgnoredDuringDaylight() throws {
        let testDate = try date(hour: 12, minute: 0)
        #expect(automation.shouldRespectWindowContacts(at: testDate, location: location) == false)
    }

    @Test("Sun below horizon: window contacts are respected")
    func windowContactsRespectedAtNight() throws {
        let testDate = try date(hour: 20, minute: 0)
        #expect(automation.shouldRespectWindowContacts(at: testDate, location: location) == true)
    }
}
