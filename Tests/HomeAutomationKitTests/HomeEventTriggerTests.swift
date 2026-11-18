//
//  HomeEventTriggerTests.swift
//  HomeAutomationKit
//

import Foundation
import HAModels
import Testing

struct HomeEventTriggerTests {
    @Test func changeNamesValueEntityAndPlace() {
        let entityId = EntityId(placeId: "Hallway", name: "Eve Motion", characteristicsName: nil, characteristic: .motionSensor)

        let trigger = HomeEvent.change(entity: EntityStorageItem(entityId: entityId, motionDetected: true)).trigger

        #expect(trigger == AutomationTrigger(kind: .entityChange, entityId: entityId, summary: "Motion · Eve Motion (Hallway)"))
    }

    @Test func timeNamesTheSchedule() {
        let date = Date(timeIntervalSince1970: 0)

        let trigger = HomeEvent.time(date: date).trigger

        #expect(trigger.kind == .time)
        #expect(trigger.entityId == nil)
        #expect(trigger.summary == "Schedule \(date.formatted(date: .omitted, time: .shortened))")
    }

    @Test func sunriseAndSunset() {
        #expect(HomeEvent.sunrise.trigger == AutomationTrigger(kind: .sunrise, entityId: nil, summary: "Sunrise"))
        #expect(HomeEvent.sunset.trigger == AutomationTrigger(kind: .sunset, entityId: nil, summary: "Sunset"))
    }
}
