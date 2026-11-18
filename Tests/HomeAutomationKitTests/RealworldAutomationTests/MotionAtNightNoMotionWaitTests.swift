//
//  MotionAtNightNoMotionWaitTests.swift
//  HomeAutomationKitTests
//

import Foundation
@testable import HAImplementations
import HAModels
import Testing

/// Presence sensors hold "motion detected" without sending new events, so the automation reads
/// the sensors before it starts the noMotionWait countdown.
@HomeManagerActor
@Suite("MotionAtNight waits for the motion to end", .timeLimit(.minutes(1)))
struct MotionAtNightNoMotionWaitTests {
    private let noMotionWait: Duration = .seconds(600)
    private let dimWait: Duration = .seconds(10)
    private let colorTemperatureDelay: Duration = .seconds(1)

    private let motion = EveMotion(query: .init(placeId: "Kueche", name: "Motion"))
    private let light = LightBulbDimmable(query: .init(placeId: "Kueche", name: "Light"))
    private let sleeper = ManualSleeper()
    private let homeManager = MockHomeAdapter()

    private var automation: MotionAtNight {
        MotionAtNight("motion-at-night",
                      noMotionWait: noMotionWait,
                      dimWait: dimWait,
                      colorTemperatureDelay: colorTemperatureDelay,
                      motionSensors: [motion],
                      lightSensor: motion,
                      lights: [light],
                      minBrightness: 0.1)
    }

    private func setMotion(_ motionDetected: Bool) {
        homeManager.storageItems.append(EntityStorageItem(entityId: motion.motionSensorId, motionDetected: motionDetected))
    }

    private func start(motionDetected: Bool?) -> Task<Void, any Error> {
        homeManager.storageItems.append(EntityStorageItem(entityId: light.switchId, isDeviceOn: true))
        if let motionDetected {
            setMotion(motionDetected)
        }
        let automation = automation
        let executeFinished = executeFinished
        let homeManager = homeManager
        let sleeper = sleeper
        return Task {
            try await automation.execute(using: homeManager, sleep: { try await sleeper.sleep(for: $0) })
            // marks the end of `execute`, so a test expecting another wait fails instead of hanging
            try await sleeper.sleep(for: executeFinished)
        }
    }

    private let executeFinished: Duration = .zero

    /// Waits until `execute` returned.
    private func finish(_ task: Task<Void, any Error>, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        try await pass(executeFinished, sourceLocation: sourceLocation)
        try await task.value
    }

    /// Waits for the next sleep, checks its duration and lets its time pass.
    private func pass(_ expected: Duration, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        let duration = await sleeper.nextSleep()
        try #require(duration == expected, sourceLocation: sourceLocation)
        sleeper.wake()
    }

    @Test("without motion the lights go off after noMotionWait and dimWait")
    func turnsOffWithoutMotion() async throws {
        let task = start(motionDetected: true)
        defer { task.cancel() }

        setMotion(false)
        try await pass(colorTemperatureDelay)
        try await pass(noMotionWait)
        try await pass(dimWait)
        try await finish(task)

        #expect(homeManager.actionCount("turnOff") == 1)
    }

    @Test("while motion is detected the sensors are polled, noMotionWait starts once the motion ended")
    func keepsWaitingWhileMotionIsDetected() async throws {
        let task = start(motionDetected: true)
        defer { task.cancel() }

        try await pass(colorTemperatureDelay)

        // the sensor still reports motion: neither dimmed nor turned off, but polled
        try #require(await sleeper.nextSleep() == MotionAtNight.motionPollInterval)
        #expect(homeManager.actionCount("setBrightness") == 1)
        sleeper.wake()

        try #require(await sleeper.nextSleep() == MotionAtNight.motionPollInterval)
        setMotion(false)
        sleeper.wake()

        // motion ended: noMotionWait, dim, off
        try #require(await sleeper.nextSleep() == noMotionWait)
        #expect(homeManager.actionCount("setBrightness") == 1)
        #expect(homeManager.actionCount("turnOff") == 0)
        sleeper.wake()

        try #require(await sleeper.nextSleep() == dimWait)
        #expect(homeManager.actionCount("setBrightness") == 2)
        sleeper.wake()
        try await finish(task)

        #expect(homeManager.actionCount("turnOff") == 1)
    }

    @Test("a motion sensor that cannot be read counts as no motion, so a dead sensor cannot keep the lights on")
    func unreadableSensorCountsAsNoMotion() async throws {
        let task = start(motionDetected: nil)
        defer { task.cancel() }

        try await pass(colorTemperatureDelay)
        try await pass(noMotionWait)
        try await pass(dimWait)
        try await finish(task)

        #expect(homeManager.actionCount("turnOff") == 1)
    }
}
