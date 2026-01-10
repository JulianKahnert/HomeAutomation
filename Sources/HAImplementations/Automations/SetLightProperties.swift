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

    /// Array of light entity IDs that will have their properties set
    public let targetLights: [EntityId]

    /// Optional RGB color to set on the lights. If nil, color will not be changed.
    public let targetColor: RGB?

    /// Optional color temperature in Kelvin to set on the lights. If nil, color temperature will not be changed.
    public let targetColorTemperature: Int?

    /// Optional brightness level (0-100) to set on the lights. If nil, brightness will not be changed.
    public let targetBrightness: Int?

    /// Duration to wait between setting each property type (RGB → color temp → brightness).
    /// Defaults to 300ms to prevent flickering.
    public let delayBetweenProperties: Duration

    public var triggerEntityIds: Set<EntityId> {
        []
    }

    public init(
        _ name: String,
        at triggerTime: Time,
        targetLights: [EntityId],
        targetColor: RGB? = nil,
        targetColorTemperature: Int? = nil,
        targetBrightness: Int? = nil,
        delayBetweenProperties: Duration = .milliseconds(300)
    ) {
        self.name = name
        self.triggerTime = triggerTime
        self.targetLights = targetLights
        self.targetColor = targetColor
        self.targetColorTemperature = targetColorTemperature
        self.targetBrightness = targetBrightness
        self.delayBetweenProperties = delayBetweenProperties
    }

    public func shouldTrigger(with event: HomeEvent, using hm: HomeManagable) async throws -> Bool {
        return triggerTime.isEqual(event)
    }

    public func execute(using hm: HomeManagable) async throws {
        log.debug("Setting light properties for \(targetLights.count) lights")

        // Apply RGB color if specified
        if let targetColor {
            log.debug("Setting RGB color: \(targetColor)")
            try await withThrowingTaskGroup(of: Void.self) { group in
                for lightId in targetLights {
                    group.addTask {
                        await hm.perform(.setRGB(lightId, rgb: targetColor))
                    }
                }
                try await group.waitForAll()
            }

            // Wait before applying next property
            try await Task.sleep(for: delayBetweenProperties)
        }

        // Apply color temperature if specified
        if let targetColorTemperature {
            log.debug("Setting color temperature: \(targetColorTemperature)K")
            // Convert Kelvin to normalized value (0...1)
            // Typical range is 2000K (warm) to 4000K (cool)
            let normalizedTemp = Float(targetColorTemperature - 2000) / 2000.0
            let clampedTemp = max(0, min(1, normalizedTemp))

            try await withThrowingTaskGroup(of: Void.self) { group in
                for lightId in targetLights {
                    group.addTask {
                        await hm.perform(.setColorTemperature(lightId, clampedTemp))
                    }
                }
                try await group.waitForAll()
            }

            // Wait before applying next property
            try await Task.sleep(for: delayBetweenProperties)
        }

        // Apply brightness if specified
        if let targetBrightness {
            log.debug("Setting brightness: \(targetBrightness)%")
            // Convert percentage (0-100) to normalized value (0...1)
            let normalizedBrightness = Float(targetBrightness) / 100.0
            let clampedBrightness = max(0, min(1, normalizedBrightness))

            try await withThrowingTaskGroup(of: Void.self) { group in
                for lightId in targetLights {
                    group.addTask {
                        await hm.perform(.setBrightness(lightId, clampedBrightness))
                    }
                }
                try await group.waitForAll()
            }
        }

        log.debug("Completed setting light properties")
    }
}
