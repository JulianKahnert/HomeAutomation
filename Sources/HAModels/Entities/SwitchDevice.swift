//
//  SwitchDevice.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 12.02.25.
//

import Shared

public protocol Validatable {
    func validate(with: HomeManagable) async throws
}

open class SwitchDevice: Codable, @unchecked Sendable, Validatable, Log {
    public let switchId: EntityId
    public let brightnessId: EntityId?
    public let colorTemperatureId: EntityId?
    public let rgbId: EntityId?

    /// Set to `true` for devices using HomeKit Adaptive Lighting
    /// to prevent manual color temperature adjustments.
    /// Default: false
    public let skipColorTemperature: Bool

    public init(switchId: EntityId, brightnessId: EntityId?, colorTemperatureId: EntityId?, rgbId: EntityId?, skipColorTemperature: Bool = false) {
        self.switchId = switchId
        self.brightnessId = brightnessId
        self.colorTemperatureId = colorTemperatureId
        self.rgbId = rgbId
        self.skipColorTemperature = skipColorTemperature
    }

    /// Returns true if this device supports color temperature adjustment
    /// either through a native colorTemperature characteristic or via RGB color control
    public var hasColorTemperatureSupport: Bool {
        !skipColorTemperature && (colorTemperatureId != nil || rgbId != nil)
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
        guard !skipColorTemperature else {
            log.debug("Skipping color temperature for device: \(switchId) (Adaptive Lighting)")
            return
        }

        assert((0...1).contains(value))

        guard hasColorTemperatureSupport else {
            log.warning("setColorTemperature called on device without support: \(switchId)")
            return
        }

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
