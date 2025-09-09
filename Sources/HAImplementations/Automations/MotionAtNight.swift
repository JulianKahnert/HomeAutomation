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
    public let noMotionWait: Duration
    public let dimWait: Duration
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

    public init(_ name: String, noMotionWait: Duration, dimWait: Duration = .seconds(10), motionSensors: [MotionSensorDevice], lightSensor: MotionSensorDevice, lights: [SwitchDevice], windowContacts: [ContactSensorDevice] = [], minBrightness: Float, maxBrightness: Float = 1, maxTemperature: Float = 1) {
        self.name = name
        self.noMotionWait = noMotionWait
        self.dimWait = dimWait
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
            // we set the color temperature, brightness and power state values seperatly so the correct temperature/brightness is already set when the turn on
            for light in lights {
                await light.setColorTemperature(to: colorTemperatureValue, with: hm)
            }
            await Task.yield()

            for light in lights {
                await light.setBrightness(to: brightnessValue, with: hm)
            }
            await Task.yield()

            for light in lights {
                await light.turnOn(with: hm)
            }

            // wait for x seconds or until this task wil be suspended
            try await Task.sleep(for: noMotionWait)
        }

        // dim lights before turning them of
        log.debug("Dimming lights before turning them off")
        for light in lights {
            // do not change the brightness, if it is currently turned off
            guard (try? await hm.getCurrentEntity(with: light.switchId).isDeviceOn ?? true) == true else { continue }
            await light.setBrightness(to: min(0.05, brightnessValue), with: hm)
        }
        try await Task.sleep(for: dimWait)

        // turn off lights
        for light in lights {
            log.debug("Turn off device \(light.switchId)")
            await light.turnOff(with: hm)
        }
    }
}
