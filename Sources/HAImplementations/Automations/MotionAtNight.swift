//
//  MotionAtNight.swift
//  
//
//  Created by Julian Kahnert on 01.07.24.
//

import Foundation
import HAModels

// Küche: min 0.5
// Wohnzimmer: min 0.3

public struct MotionAtNight: Automatable {
    // threshold under which the automation should be triggered
    private static let thresholdInLux = 60.0

    public var isActive = true
    public let name: String
    /// Time to wait after last motion detection before starting the dim/off sequence
    public private(set) var noMotionWait: Duration = .seconds(60)
    /// Time to keep lights dimmed before turning them off completely
    public private(set) var dimWait: Duration = .seconds(10)
    /// Time to wait between turning on lights and setting color temperature to prevent flickering
    public private(set) var colorTemperatureDelay: Duration = .seconds(1)
    public let motionSensors: [MotionSensorDevice]
    public let lightSensor: MotionSensorDevice
    public let windowContacts: [ContactSensorDevice]
    public let minBrightness: Float
    public let maxBrightness: Float
    public let maxTemperature: Float

    public let lights: [SwitchDevice]
    public var triggerEntityIds: Set<EntityId> {
        Set(motionSensors.map(\.motionSensorId) + windowContacts.map(\.contactSensorId) + [lightSensor.lightSensorId!])
    }

    public init(_ name: String, noMotionWait: Duration? = nil, dimWait: Duration? = nil, colorTemperatureDelay: Duration? = nil, motionSensors: [MotionSensorDevice], lightSensor: MotionSensorDevice, lights: [SwitchDevice], windowContacts: [ContactSensorDevice] = [], minBrightness: Float, maxBrightness: Float = 1, maxTemperature: Float = 1) {
        self.name = name
        if let noMotionWait { self.noMotionWait = noMotionWait }
        if let dimWait { self.dimWait = dimWait }
        if let colorTemperatureDelay { self.colorTemperatureDelay = colorTemperatureDelay }
        self.motionSensors = motionSensors
        self.lightSensor = lightSensor
        self.lights = lights
        self.windowContacts = windowContacts
        self.minBrightness = minBrightness
        self.maxBrightness = maxBrightness
        self.maxTemperature = maxTemperature
    }

    public func shouldTrigger(with event: HomeEvent, using hm: HomeManagable) async throws -> Bool {
        let sensorIds = Set(motionSensors.map(\.motionSensorId)).union(windowContacts.map(\.contactSensorId))
        guard case let HomeEvent.change(item) = event,
              sensorIds.contains(item.entityId) else {
            return false
        }

        // was any motion sensor triggered
        let motionDetected = await motionSensors.asyncMap({ motionSensor in
            do {
                return try await motionSensor.motionDetectedState(with: hm)
            } catch {
                log.critical("Failed to get motion sensor data - \(error)")
                return false
            }
        }).contains { $0 }

        var illuminance: Measurement<UnitIlluminance>?
        do {
            illuminance = try await lightSensor.illuminanceState(with: hm)
        } catch {
            log.critical("Failed to get illuminance state - \(error)")
        }
        guard let illuminance else { return false }

        let shouldTrigger = motionDetected && illuminance.converted(to: .lux).value < Self.thresholdInLux
        log.debug("Should trigger [\(shouldTrigger)] - [motion: \(motionDetected), \(illuminance)]")
        return shouldTrigger
    }

    public func execute(using hm: HomeManagable) async throws {
        let isWindowOpen = await windowContacts.asyncMap({ windowSensor in
            do {
                return try await windowSensor.isContactOpen(with: hm)
            } catch {
                log.critical("Failed to get contact sensor - \(error)")
                return false
            }
        }).contains { $0 }

        let colorTemperatureValue = getNormalizedColorTemperatureValue().scale(to: 0.1...maxTemperature)
        let brightnessValue = getNormalizedBrightnessValue().scale(to: minBrightness...maxBrightness)

        if !isWindowOpen {
            log.debug("Adjusting lights")

            // We reduce the number of invocations/calls to the device to avoid flickering of it.
            // Note: First set brightness, then color temperature
            await withTaskGroup(of: Void.self) { group in
                // Each light runs its own sequence: turn on -> wait -> set color temperature
                for light in lights {
                    group.addTask {
                        // Turn on the light
                        if light.brightnessId != nil {
                            await light.setBrightness(to: brightnessValue, with: hm)
                        } else {
                            await light.turnOn(with: hm)
                        }

                        // Wait before adjusting color temperature to prevent flickering
                        try? await Task.sleep(for: colorTemperatureDelay)

                        // Set color temperature if supported
                        if light.hasColorTemperatureSupport {
                            await light.setColorTemperature(to: colorTemperatureValue, with: hm)
                        }
                    }
                }

                // Wait for all lights to complete their sequence before proceeding
                await group.waitForAll()
            }

            // wait for x seconds or until this task wil be suspended
            try await Task.sleep(for: noMotionWait)
        }

        // dim lights before turning them off
        log.debug("Dimming lights before turning them off")
        await withTaskGroup(of: Void.self) { group in
            for light in lights {
                group.addTask {
                    // do not change the brightness, if it is currently turned off
                    guard (try? await hm.getCurrentEntity(with: light.switchId).isDeviceOn ?? true) == true else { return }
                    await light.setBrightness(to: min(0.05, brightnessValue), with: hm)
                }
            }

            await group.waitForAll()
        }
        try await Task.sleep(for: dimWait)

        // turn off lights in parallel
        await withTaskGroup(of: Void.self) { group in
            for light in lights {
                group.addTask {
                    log.debug("Turn off device \(light.switchId)")
                    await light.turnOff(with: hm)
                }
            }

            await group.waitForAll()
        }
    }
}
