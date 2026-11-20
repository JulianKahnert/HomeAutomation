//
//  RadiatorDevice.swift
//  HAModels
//

import Shared

/// A radiator thermostat (glossary: radiator). Named by capability, not by manufacturer: other
/// manufacturers than Eve may follow.
open class RadiatorDevice: Codable, @unchecked Sendable, Validatable, Log {
    /// `Active` of the HeaterCooler service: written `false` to switch the radiator off.
    public let heatingId: EntityId
    /// The heating threshold, the target temperature the radiator holds.
    public let targetTemperatureId: EntityId

    /// The radiator's own temperature measurement (same device as `heatingId`).
    public var temperatureId: EntityId { sibling(.temperatureSensor) }
    /// The radiator's valve opening in percent (same device as `heatingId`).
    public var valvePositionId: EntityId { sibling(.valvePosition) }

    private func sibling(_ characteristic: CharacteristicsType) -> EntityId {
        EntityId(placeId: heatingId.placeId, name: heatingId.name, characteristicsName: nil, characteristic: characteristic)
    }

    public init(heatingId: EntityId, targetTemperatureId: EntityId) {
        self.heatingId = heatingId
        self.targetTemperatureId = targetTemperatureId
    }

    /// Sets the radiator active and writes its target temperature.
    public func setTarget(_ celsius: Double, with hm: HomeManagable) async {
        await hm.perform(.setHeating(heatingId, active: true))
        await hm.perform(.setTargetTemperature(targetTemperatureId, celsius: celsius))
    }

    /// Writes the radiator off (`Active = 0`); frost and valve protection stay with the thermostat itself.
    public func turnOff(with hm: HomeManagable) async {
        await hm.perform(.setHeating(heatingId, active: false))
    }

    public func validate(with hm: any EntityValidator) async throws {
        try await hm.findEntity(heatingId)
        try await hm.findEntity(targetTemperatureId)
    }
}
