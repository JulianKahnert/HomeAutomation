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
    /// What makes `MotionAtNight` look at the sensors.
    enum Trigger: CaseIterable, CustomTestStringConvertible {
        case motionReport, serverStart

        var testDescription: String {
            switch self {
            case .motionReport: "motion report"
            case .serverStart: "server start"
            }
        }
    }

    private static let sensor = EntityId.Query(placeId: "Kueche", name: "Motion")
    private let motion = EveMotion(query: sensor)
    private let lightSensorId = EntityId(query: sensor, characteristic: .lightSensor)
    private let light = LightBulbDimmable(query: .init(placeId: "Kueche", name: "Light"))
    private let homeManager = MockHomeAdapter()

    private var automation: MotionAtNight {
        MotionAtNight("motion-at-night", motionSensors: [motion], lightSensor: motion, lights: [light], minBrightness: 0.1)
    }

    /// Sets the sensor's current state and returns the event of `trigger` for it.
    private func event(_ trigger: Trigger, motionDetected: Bool, lux: Double?) -> HomeEvent {
        if let lux {
            homeManager.storageItems.append(EntityStorageItem(entityId: lightSensorId, illuminance: .init(value: lux, unit: .lux)))
        }
        let item = EntityStorageItem(entityId: motion.motionSensorId, motionDetected: motionDetected)
        homeManager.storageItems.append(item)
        switch trigger {
        case .motionReport: return .change(entity: item)
        case .serverStart: return .serverStarted
        }
    }

    @Test("motion below the lux threshold triggers", arguments: Trigger.allCases)
    func triggersOnMotionInTheDark(trigger: Trigger) async throws {
        let event = event(trigger, motionDetected: true, lux: 59)

        #expect(try await automation.shouldTrigger(with: event, using: homeManager))
    }

    @Test("no motion does not trigger, even in the dark", arguments: Trigger.allCases)
    func noTriggerWithoutMotion(trigger: Trigger) async throws {
        let event = event(trigger, motionDetected: false, lux: 5)

        #expect(try await automation.shouldTrigger(with: event, using: homeManager) == false)
    }

    @Test("motion at or above the lux threshold does not trigger", arguments: Trigger.allCases, [60.0, 500])
    func noTriggerWhenBright(trigger: Trigger, lux: Double) async throws {
        let event = event(trigger, motionDetected: true, lux: lux)

        #expect(try await automation.shouldTrigger(with: event, using: homeManager) == false)
    }

    @Test("motion does not trigger when the illuminance cannot be read", arguments: Trigger.allCases)
    func noTriggerWithoutIlluminance(trigger: Trigger) async throws {
        let event = event(trigger, motionDetected: true, lux: nil)

        #expect(try await automation.shouldTrigger(with: event, using: homeManager) == false)
    }
}
