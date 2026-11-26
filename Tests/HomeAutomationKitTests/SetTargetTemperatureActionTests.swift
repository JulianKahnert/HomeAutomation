//
//  SetTargetTemperatureActionTests.swift
//  HomeAutomationKit
//

import Foundation
@testable import HAModels
import Testing

struct SetTargetTemperatureActionTests {
    private let id = EntityId(placeId: "Kitchen", name: "Radiator", characteristicsName: nil, characteristic: .targetTemperature)

    @Test("The action names its entity and the written value")
    func describesItself() {
        let action = HomeManagableAction.setTargetTemperature(id, celsius: 21.5)

        #expect(action.entityId == id)
        #expect(action.actionName == "setTargetTemperature")
        #expect(action.description == "setTargetTemperature(celsius: 21.5)")
    }

    @Test("Rounding goes to half degrees, the step of the radiators")
    func roundsToHalfDegrees() {
        #expect(HomeManagableAction.setTargetTemperature(id, celsius: 20.3).rounded() == .setTargetTemperature(id, celsius: 20.5))
        #expect(HomeManagableAction.setTargetTemperature(id, celsius: 20.2).rounded() == .setTargetTemperature(id, celsius: 20.0))
        #expect(HomeManagableAction.setTargetTemperature(id, celsius: 21.75).rounded() == .setTargetTemperature(id, celsius: 22.0))
    }

    @Test("A different target at the device contradicts the command, the same one confirms it")
    func contradiction() {
        let action = HomeManagableAction.setTargetTemperature(id, celsius: 21.0)

        #expect(action.isContradicted(by: EntityStorageItem(entityId: id, targetTemperatureInC: 19.0)) == true)
        #expect(action.isContradicted(by: EntityStorageItem(entityId: id, targetTemperatureInC: 21.0)) == false)
        #expect(action.isContradicted(by: EntityStorageItem(entityId: id, targetTemperatureInC: nil)) == false)
    }

    @Test("The action survives the adapter wire")
    func codableRoundTrip() throws {
        let action = HomeManagableAction.setTargetTemperature(id, celsius: 18.5)
        let decoded = try JSONDecoder().decode(HomeManagableAction.self, from: JSONEncoder().encode(action))
        #expect(decoded == action)
    }
}
