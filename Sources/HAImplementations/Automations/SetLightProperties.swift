//
//  SetLightProperties.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 10.01.26.
//

import Foundation
import HAModels

public struct SetLightProperties: Automatable {
    public var isActive = true
    public let name: String

    /// The time when this automation should trigger
    public let triggerTime: Time

    /// The array of light devices to control.
    public let lights: [SwitchDevice]

    /// Optional RGB color to set on the lights.
    public let color: RGB?

    /// Optional color temperature as a normalized value between 0 and 1.
    /// Where 0 represents the warmest (lowest Kelvin) and 1 represents the coolest (highest Kelvin).
    public let colorTemperature: Double?

    /// Optional brightness as a normalized value between 0 and 1.
    /// Where 0 is off and 1 is maximum brightness.
    public let brightness: Double?

    /// Duration to wait between setting each property type (RGB → color temp → brightness).
    /// Defaults to 300ms to prevent flickering.
    public let delayBetweenProperties: Duration

    public var triggerEntityIds: Set<EntityId> {
        []
    }

    public init(
        _ name: String,
        at triggerTime: Time,
        lights: [SwitchDevice],
        color: RGB? = nil,
        colorTemperature: Double? = nil,
        brightness: Double? = nil,
        delayBetweenProperties: Duration = .milliseconds(300)
    ) {
        self.name = name
        self.triggerTime = triggerTime
        self.lights = lights
        self.color = color
        self.colorTemperature = colorTemperature
        self.brightness = brightness
        self.delayBetweenProperties = delayBetweenProperties
    }

    public func shouldTrigger(with event: HomeEvent, using hm: HomeManagable) async throws -> Bool {
        return triggerTime.isEqual(event)
    }

    public func execute(using hm: HomeManagable) async throws {
        log.debug("Setting light properties for \(lights.count) lights")

        // Apply RGB color if specified
        if let color {
            log.debug("Setting RGB color: \(color)")
            try await withThrowingTaskGroup(of: Void.self) { group in
                for light in lights {
                    group.addTask {
                        await light.setColor(to: color, with: hm)
                    }
                }
                try await group.waitForAll()
            }

            // Wait before applying next property
            try await Task.sleep(for: delayBetweenProperties)
        }

        // Apply color temperature if specified
        if let colorTemperature {
            log.debug("Setting color temperature: \(colorTemperature)")
            try await withThrowingTaskGroup(of: Void.self) { group in
                for light in lights {
                    group.addTask {
                        await light.setColorTemperature(to: Float(colorTemperature), with: hm)
                    }
                }
                try await group.waitForAll()
            }

            // Wait before applying next property
            try await Task.sleep(for: delayBetweenProperties)
        }

        // Apply brightness if specified
        if let brightness {
            log.debug("Setting brightness: \(brightness)")
            try await withThrowingTaskGroup(of: Void.self) { group in
                for light in lights {
                    group.addTask {
                        await light.setBrightness(to: Float(brightness), with: hm)
                    }
                }
                try await group.waitForAll()
            }
        }

        log.debug("Completed setting light properties")
    }
}
