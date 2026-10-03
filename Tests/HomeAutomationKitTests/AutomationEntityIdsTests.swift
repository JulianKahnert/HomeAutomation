//
//  AutomationEntityIdsTests.swift
//  HomeAutomationKit
//

import HAImplementations
import HAModels
import Testing

struct AutomationEntityIdsTests {
    @Test func involvedEntityIdsSkipBatterySensorsAndDuplicates() throws {
        let motion = EveMotion(query: .init(placeId: "room1", name: "motion1"))
        let automation = MotionAtNight("night", motionSensors: [motion], lightSensor: motion, lights: [], minBrightness: 0.1)
        let lightSensorId = try #require(motion.lightSensorId)

        let ids = automation.involvedEntityIds

        #expect(Set(ids) == [motion.motionSensorId, lightSensorId])
        #expect(ids.count == 2)
    }
}
