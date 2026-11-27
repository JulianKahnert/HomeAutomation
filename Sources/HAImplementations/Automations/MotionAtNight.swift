//
//  MotionAtNight.swift
//  
//
//  Created by Julian Kahnert on 01.07.24.
//

import Foundation
import HAModels

public struct MotionAtNight: Automatable {
    public var isActive = true
    public let name: String
    /// Time to wait after no motion sensor reports motion before starting the dim/off sequence
    public private(set) var noMotionWait: Duration = .seconds(60)
    /// Time to keep lights dimmed before turning them off completely
    public private(set) var dimWait: Duration = .seconds(10)
    /// Time to wait between turning on lights and setting color temperature to prevent flickering
    public private(set) var colorTemperatureDelay: Duration = .seconds(1)
    /// How often the motion sensors are read while they report motion, before `noMotionWait` starts.
    static let motionPollInterval: Duration = .seconds(30)
    public let motionSensors: [MotionSensorDevice]
    public let lightSensor: MotionSensorDevice
    public let windowContacts: [ContactSensorDevice]
    public let minBrightness: Float
    public let maxBrightness: Float
    public let maxTemperature: Float

    public let lights: [SwitchDevice]
    public var triggerEntityIds: Set<EntityId> {
        var ids = Set(motionSensors.map(\.motionSensorId) + windowContacts.map(\.contactSensorId))
        if let lightSensorId = lightSensor.lightSensorId {
            ids.insert(lightSensorId)
        }
        return ids
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

    /// A server start follows the same rule as a motion report, so motion that is still held
    /// switches the light on again after a restart.
    public func shouldTrigger(with event: HomeEvent, using hm: HomeManagable) async throws -> Bool {
        let sensorIds = Set(motionSensors.map(\.motionSensorId)).union(windowContacts.map(\.contactSensorId))
        switch event {
        case .change(let item):
            guard sensorIds.contains(item.entityId) else { return false }
        case .serverStarted:
            break
        case .time, .sunrise, .sunset, .configDeployed, .fireplaceChanged:
            return false
        }

        let motionDetected = await isMotionDetected(using: hm)

        var illuminance: Measurement<UnitIlluminance>?
        do {
            illuminance = try await lightSensor.illuminanceState(with: hm)
        } catch {
            log.warning("Failed to get illuminance state - \(error)")
        }
        guard let illuminance else { return false }

        let shouldTrigger = motionDetected && illuminance.converted(to: .lux).value < MotionAtNightConstants.thresholdInLux
        log.debug("Should trigger [\(shouldTrigger)] - [motion: \(motionDetected), \(illuminance)]")
        return shouldTrigger
    }

    public func triggerSummary(for event: HomeEvent, using hm: HomeManagable) async -> String? {
        do {
            let illuminance = try await lightSensor.illuminanceState(with: hm)
            return "at \(Int(illuminance.converted(to: .lux).value.rounded())) lx"
        } catch {
            log.warning("Failed to get illuminance for the trigger summary - \(error)")
            return nil
        }
    }

    /// Window contacts only matter after dark — a lit room with an open window draws insects,
    /// which is not a concern in daylight. Respected unless the sun position is unavailable, so
    /// an unknown sun state never silently switches insect protection off.
    func shouldRespectWindowContacts(at date: Date, location: Location) -> Bool {
        guard let isSunBelowHorizon = Sun.isSunBelowHorizon(for: date, latitude: location.latitude, longitude: location.longitude) else {
            log.warning("Failed to determine sun position - respecting window contacts")
            return true
        }
        return isSunBelowHorizon
    }

    public func execute(using hm: HomeManagable) async throws {
        try await execute(using: hm, sleep: { try await Task.sleep(for: $0) })
    }

    /// `sleep` stands in for `Task.sleep`, so tests can drive the waits without real time.
    func execute(using homeManager: HomeManagable, sleep: @escaping @Sendable (Duration) async throws -> Void) async throws {
        let location = await homeManager.getLocation()
        let isWindowOpen: Bool
        if shouldRespectWindowContacts(at: Date(), location: location) {
            isWindowOpen = await windowContacts.asyncMap({ windowSensor in
                do {
                    return try await windowSensor.isContactOpen(with: homeManager)
                } catch {
                    log.warning("Failed to get contact sensor - \(error)")
                    return false
                }
            }).contains { $0 }
        } else {
            isWindowOpen = false
        }

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
                            await light.setBrightness(to: brightnessValue, with: homeManager)
                        } else {
                            await light.turnOn(with: homeManager)
                        }

                        // Wait before adjusting color temperature to prevent flickering
                        try? await sleep(colorTemperatureDelay)

                        // Set color temperature if supported
                        if light.hasColorTemperatureSupport {
                            await light.setColorTemperature(to: colorTemperatureValue, with: homeManager)
                        }
                    }
                }

                // Wait for all lights to complete their sequence before proceeding
                await group.waitForAll()
            }

            // Presence sensors hold "motion detected" without sending new events, so the countdown
            // starts only once no sensor reports motion. A new motion trigger cancels this run.
            while await isMotionDetected(using: homeManager) {
                try await sleep(Self.motionPollInterval)
            }
            try await sleep(noMotionWait)
        }

        // dim lights before turning them off
        log.debug("Dimming lights before turning them off")
        await withTaskGroup(of: Void.self) { group in
            for light in lights {
                group.addTask {
                    // do not change the brightness, if it is currently turned off
                    guard (try? await homeManager.getCurrentEntity(with: light.switchId).isDeviceOn ?? true) == true else { return }
                    await light.setBrightness(to: min(0.05, brightnessValue), with: homeManager)
                }
            }

            await group.waitForAll()
        }
        try await sleep(dimWait)

        // turn off lights in parallel
        await withTaskGroup(of: Void.self) { group in
            for light in lights {
                group.addTask {
                    log.debug("Turn off device \(light.switchId)")
                    await light.turnOff(with: homeManager)
                }
            }

            await group.waitForAll()
        }
    }

    /// Whether any motion sensor reports motion. A sensor that cannot be read counts as "no motion",
    /// so an unreachable or dead sensor cannot keep the lights on forever.
    private func isMotionDetected(using homeManager: HomeManagable) async -> Bool {
        await motionSensors.asyncMap({ motionSensor in
            do {
                return try await motionSensor.motionDetectedState(with: homeManager)
            } catch {
                log.warning("Failed to get motion sensor data, counting it as no motion - \(error)")
                return false
            }
        }).contains { $0 }
    }
}
