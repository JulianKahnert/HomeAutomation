//
//  HeatingWriteTests.swift
//  HomeAutomationKit
//

import Foundation
import HAModels
import Testing

struct HeatingWriteTests {
    private let radiator = EntityId(placeId: "Kitchen", name: "Radiator", characteristicsName: nil, characteristic: .targetTemperature)

    @Test("A target temperature write keeps reason, written value and plan target")
    func targetWrite() throws {
        let context = HeatingWriteContext.Context(reason: .plan, planTargetInC: 21)

        let write = try #require(HeatingWrite(action: .setTargetTemperature(radiator, celsius: 21), context: context))

        #expect(write.reason == .plan)
        #expect(write.targetTemperatureInC == 21)
        #expect(write.planTargetInC == 21)
        #expect(write.isActive == nil)
        #expect(write.placeId == "Kitchen")
    }

    @Test("An off write records the active flag and no plan target for a window reason")
    func offWrite() throws {
        let write = try #require(HeatingWrite(action: .setHeating(radiator, active: false), context: .init(reason: .window)))

        #expect(write.isActive == false)
        #expect(write.targetTemperatureInC == nil)
        #expect(write.planTargetInC == nil)
    }

    @Test("Other actions are not heating writes")
    func otherActions() {
        let switcher = EntityId(placeId: "Kitchen", name: "Light", characteristicsName: nil, characteristic: .switcher)
        #expect(HeatingWrite(action: .turnOn(switcher), context: .init(reason: .system)) == nil)
    }

    @Test("A write survives the database round trip as JSON")
    func codable() throws {
        let write = HeatingWrite(timestamp: Date(timeIntervalSince1970: 100), entityId: radiator, reason: .system, actionName: "setTargetTemperature", targetTemperatureInC: 19.5, planTargetInC: 19.5)
        let decoded = try JSONDecoder().decode(HeatingWrite.self, from: JSONEncoder().encode(write))
        #expect(decoded == write)
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
        #expect(item.planTargetInC == nil)
        #expect(item.actionName == "setHeating")
    }

    @Test("An entry with reason and plan target round-trips")
    func newEntryRoundTrips() throws {
        let radiator = EntityId(placeId: "Kitchen", name: "Radiator", characteristicsName: nil, characteristic: .targetTemperature)
        let item = ActionLogItem(action: .setTargetTemperature(radiator, celsius: 20), reason: .plan, planTargetInC: 20)

        let decoded = try JSONDecoder().decode(ActionLogItem.self, from: JSONEncoder().encode(item))

        #expect(decoded.reason == .plan)
        #expect(decoded.planTargetInC == 20)
    }
}
