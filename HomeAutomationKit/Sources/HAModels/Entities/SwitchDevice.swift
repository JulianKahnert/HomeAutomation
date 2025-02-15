//
//  SwitchDevice.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 12.02.25.
//

public protocol Validatable {
    func validate(with: HomeManagable) async throws
}

open class SwitchDevice: Codable, @unchecked Sendable, Validatable {
    public let switchId: EntityId
    public let brightnessId: EntityId?
    public let colorTemperatureId: EntityId?
    public let rgbId: EntityId?

    public init(switchId: EntityId, brightnessId: EntityId?, colorTemperatureId: EntityId?, rgbId: EntityId?) {
        self.switchId = switchId
        self.brightnessId = brightnessId
        self.colorTemperatureId = colorTemperatureId
        self.rgbId = rgbId
    }

    public func turnOn(with hm: HomeManagable) async {
        await hm.perform(.turnOn(switchId))
    }

    public func turnOff(with hm: HomeManagable) async {
        await hm.perform(.turnOff(switchId))
    }

    /// Brightness in percent normalized to 0...1 (dark ... bright)
    public func setBrightness(to value: Float, with hm: HomeManagable) async {
        guard let brightnessId else { return }
        await hm.perform(.setBrightness(brightnessId, value))
    }

    /// Color temperature normalized to 0...1 (warm ... white)
    public func setColorTemperature(to value: Float, with hm: any HomeManagable) async {
        assert((0...1).contains(value))

        if let colorTemperatureId {
            await hm.perform(.setColorTemperature(colorTemperatureId, value))
        } else if let rgbId {
            let rgb = componentsForColorTemperature(normalzied: value)
            await hm.perform(.setRGB(rgbId, rgb: rgb))
        }
    }

    /// Color of this light
    public func setColor(to rgb: RGB, with hm: any HomeManagable) async {
        guard let rgbId else { return }
        await hm.perform(.setRGB(rgbId, rgb: rgb))
    }

    public func validate(with hm: HomeManagable) async throws {
        try await hm.findEntity(switchId)
        if let brightnessId {
            try await hm.findEntity(brightnessId)
        }
        if let colorTemperatureId {
            try await hm.findEntity(colorTemperatureId)
        }
        if let rgbId {
            try await hm.findEntity(rgbId)
        }
    }
}
