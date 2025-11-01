//
//  AutomatableTests.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 20.07.24.
//

import Foundation
@testable import HAApplicationLayer
@testable import HAImplementations
import HAModels
import Testing

struct AutomatableTests {

    let windowContact = WindowContactSensor(query: .init(placeId: "room1", name: "contact1"))
    let automation: WindowOpen

    init() {
        automation = WindowOpen("window-open",
                                windowContact: windowContact)
    }

    @Test("Test if all entityIds were found in a WindowOpen automation")
    func windowOpenAutomationEntityIds() async throws {
        // prepare

        // run
        let entityIds = automation.triggerEntityIds

        // assert
        #expect(entityIds == [EntityId(placeId: "room1", name: "contact1", characteristicsName: nil, characteristic: .contactSensor)] )
    }
}
