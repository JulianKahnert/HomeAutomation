//
//  Other.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 20.07.24.
//

import Foundation
@testable import HAImplementations
@testable import HAModels
import Testing

struct ConfigTests {

    @Test("Test config triggerEntityIds reflection equality")
    func normalizeElevation() throws {
        let device1 = EveMotion(query: .init(placeId: "room1", name: "motion1"))
        let device2 = GenericSwitch(query: .init(placeId: "room1", name: "switch1"))
        let device3 = WindowContactSensor(query: .init(placeId: "room1", name: "contact1"))
        let automation = MotionAtNight("motion-at-night", noMotionWait: .milliseconds(50), motionSensors: [device1], lightSensor: device1, lights: [device2], windowContacts: [device3], minBrightness: 0.1)
        let automations = [automation]
        let entityIds = Set(automations.flatMap(\.triggerEntityIds))

        let refEntityIds = Set([
            EntityId(placeId: "room1", name: "motion1", characteristicsName: nil, characteristic: .motionSensor),
            EntityId(placeId: "room1", name: "motion1", characteristicsName: nil, characteristic: .lightSensor),
            EntityId(placeId: "room1", name: "contact1", characteristicsName: nil, characteristic: .contactSensor)
        ])

        #expect(entityIds == refEntityIds)
    }
}
