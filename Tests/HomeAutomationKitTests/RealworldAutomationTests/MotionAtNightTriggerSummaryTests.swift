//
//  MotionAtNightTriggerSummaryTests.swift
//  HomeAutomationKit
//

import Foundation
import HAImplementations
import HAModels
import Testing

@HomeManagerActor
struct MotionAtNightTriggerSummaryTests {
    private let motion = EveMotion(query: .init(placeId: "room1", name: "motion1"))

    @Test func summaryNamesTheIlluminanceAtTriggerTime() async throws {
        let automation = MotionAtNight("night", motionSensors: [motion], lightSensor: motion, lights: [], minBrightness: 0.1)
        let homeManager = MockHomeAdapter()
        let lightSensorId = try #require(motion.lightSensorId)
        homeManager.storageItems = [EntityStorageItem(entityId: lightSensorId, illuminance: .init(value: 3.2, unit: .lux))]

        let summary = await automation.triggerSummary(for: .sunset, using: homeManager)

        #expect(summary == "at 3 lx")
    }
}
