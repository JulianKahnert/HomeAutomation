//
//  AutomatableTests.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 20.07.24.
//

import Foundation
@testable import HAApplicationLayer
@testable import HAConfig
@testable import HAImplementations
@testable import HomeAutomationKit
import Testing

struct AutomatableTests {

    let noMotionWait: Duration = .milliseconds(200)
    let dimWait: Duration = .milliseconds(50)
    let deviceEveMotion = EveMotion(query: .init(placeId: "room1", name: "motion1"))
    let deviceEveMotion2 = EveMotion(query: .init(placeId: "room2", name: "motion2", characteristicsName: "characteristicName2"))
    let windowContact: WindowContactSensible = WindowContactSensor(query: .init(placeId: "room1", name: "contact1"))
    let automation1: GoodNight
    let automation2: WindowOpen

    init() {
        automation1 = GoodNight(at: Time(hour: 0, minute: 0),
                                 motionSensors: [deviceEveMotion, deviceEveMotion2],
                                 motionWait: .milliseconds(100))
        automation2 = WindowOpen(windowContact: windowContact)
    }

    @Test("Test if all entityIds were found in a GoodNight automation")
    func goodNightAutomationEntityIds() async throws {
        // prepare

        // run
        let entityIds = automation1.triggerEntityIds

        // assert
        #expect(entityIds.isEmpty)
    }

    @Test("Test if all entityIds were found in a WindowOpen automation")
    func windowOpenAutomationEntityIds() async throws {
        // prepare

        // run
        let entityIds = automation2.triggerEntityIds

        // assert
        #expect(entityIds == [EntityId(placeId: "room1", name: "contact1", characteristicsName: nil, characteristic: .contactSensor)] )
    }
}
