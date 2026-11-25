//
//  MotionAtNightTriggerRuleTests.swift
//  HomeAutomationKitTests
//

import Foundation
import HAImplementations
import HAModels
import Testing

/// Pins when a motion report or a server start starts `MotionAtNight`: motion detected and darker than the lux threshold.
@HomeManagerActor
@Suite("MotionAtNight trigger rule")
struct MotionAtNightTriggerRuleTests {
    private let motion = EveMotion(query: .init(placeId: "Kueche", name: "Motion"))
    private let light = LightBulbDimmable(query: .init(placeId: "Kueche", name: "Light"))
    private let homeManager = MockHomeAdapter()

    private var automation: MotionAtNight {
        MotionAtNight("motion-at-night", motionSensors: [motion], lightSensor: motion, lights: [light], minBrightness: 0.1)
    }

    /// Sets the sensor's current state and returns the motion report for it.
    private func report(motionDetected: Bool, lux: Double?) throws -> HomeEvent {
        let item = try setState(motionDetected: motionDetected, lux: lux)
        return .change(entity: item)
    }

    /// Sets the sensor's current state and returns its motion state.
    @discardableResult
    private func setState(motionDetected: Bool, lux: Double?) throws -> EntityStorageItem {
        if let lux {
            let lightSensorId = try #require(motion.lightSensorId)
            homeManager.storageItems.append(EntityStorageItem(entityId: lightSensorId, illuminance: .init(value: lux, unit: .lux)))
        }
        let item = EntityStorageItem(entityId: motion.motionSensorId, motionDetected: motionDetected)
        homeManager.storageItems.append(item)
        return item
    }

    @Test("motion below the lux threshold triggers")
    func triggersOnMotionInTheDark() async throws {
        let event = try report(motionDetected: true, lux: 59)

        #expect(try await automation.shouldTrigger(with: event, using: homeManager))
    }

    @Test("a report without motion does not trigger, even in the dark")
    func noTriggerWithoutMotion() async throws {
        let event = try report(motionDetected: false, lux: 5)

        #expect(try await automation.shouldTrigger(with: event, using: homeManager) == false)
    }

    @Test("motion at or above the lux threshold does not trigger", arguments: [60.0, 500])
    func noTriggerWhenBright(lux: Double) async throws {
        let event = try report(motionDetected: true, lux: lux)

        #expect(try await automation.shouldTrigger(with: event, using: homeManager) == false)
    }

    @Test("motion does not trigger when the illuminance cannot be read")
    func noTriggerWithoutIlluminance() async throws {
        let event = try report(motionDetected: true, lux: nil)

        #expect(try await automation.shouldTrigger(with: event, using: homeManager) == false)
    }

    // MARK: - Server start

    @Test("a server start with motion below the lux threshold triggers")
    func serverStartTriggersOnMotionInTheDark() async throws {
        try setState(motionDetected: true, lux: 59)

        #expect(try await automation.shouldTrigger(with: .serverStarted, using: homeManager))
    }

    @Test("a server start without motion does not trigger, even in the dark")
    func serverStartNoTriggerWithoutMotion() async throws {
        try setState(motionDetected: false, lux: 5)

        #expect(try await automation.shouldTrigger(with: .serverStarted, using: homeManager) == false)
    }

    @Test("a server start with motion at or above the lux threshold does not trigger", arguments: [60.0, 500])
    func serverStartNoTriggerWhenBright(lux: Double) async throws {
        try setState(motionDetected: true, lux: lux)

        #expect(try await automation.shouldTrigger(with: .serverStarted, using: homeManager) == false)
    }

    @Test("a server start with motion does not trigger when the illuminance cannot be read")
    func serverStartNoTriggerWithoutIlluminance() async throws {
        try setState(motionDetected: true, lux: nil)

        #expect(try await automation.shouldTrigger(with: .serverStarted, using: homeManager) == false)
    }
}
