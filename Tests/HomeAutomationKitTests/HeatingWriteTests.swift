//
//  HeatingWriteTests.swift
//  HomeAutomationKit
//

import Foundation
import HAModels
import Testing

struct HeatingWriteTests {
    private let radiator = EntityId(placeId: "Kitchen", name: "Radiator", characteristicsName: nil, characteristic: .targetTemperature)

    @Test("A target temperature command reads as its reason and written value")
    func targetWrite() {
        let write = ActionLogItem(action: .setTargetTemperature(radiator, celsius: 21), reason: .plan)

        #expect(write.isExecutedHeatingWrite)
        #expect(write.reason == .plan)
        #expect(write.targetTemperatureInC == 21)
        #expect(write.isActive == nil)
        #expect(write.placeId == "Kitchen")
    }

    @Test("An off command reads as the active flag")
    func offWrite() {
        let write = ActionLogItem(action: .setHeating(radiator, active: false), reason: .window)

        #expect(write.isActive == false)
        #expect(write.targetTemperatureInC == nil)
    }

    @Test("Other commands, cache hits and commands without a reason are no heating writes")
    func otherActions() {
        let switcher = EntityId(placeId: "Kitchen", name: "Light", characteristicsName: nil, characteristic: .switcher)
        #expect(!ActionLogItem(action: .turnOn(switcher), reason: .system).isExecutedHeatingWrite)
        #expect(!ActionLogItem(action: .setHeating(radiator, active: true), status: .cacheHit, reason: .plan).isExecutedHeatingWrite)
        #expect(!ActionLogItem(action: .setHeating(radiator, active: true)).isExecutedHeatingWrite)
    }
}

struct ActionLogItemCompatibilityTests {
    @Test("An entry written before the reason existed still loads, without a reason")
    func oldEntryLoads() throws {
        let json = """
        {"id":"7B9F4B7A-0000-4000-8000-000000000001","timestamp":0,
         "entityId":{"placeId":"Kitchen","name":"Radiator","characteristicType":"heating"},
         "actionName":"setHeating","detailDescription":"setHeating(active: true)","status":"executed"}
        """
        let item = try JSONDecoder().decode(ActionLogItem.self, from: Data(json.utf8))

        #expect(item.reason == nil)
        #expect(item.actionName == "setHeating")
    }

    @Test("An entry with a reason round-trips")
    func newEntryRoundTrips() throws {
        let radiator = EntityId(placeId: "Kitchen", name: "Radiator", characteristicsName: nil, characteristic: .targetTemperature)
        let item = ActionLogItem(action: .setTargetTemperature(radiator, celsius: 20), reason: .plan)

        let decoded = try JSONDecoder().decode(ActionLogItem.self, from: JSONEncoder().encode(item))

        #expect(decoded.reason == .plan)
        #expect(decoded.targetTemperatureInC == 20)
    }
}
