//
//  MotionAtNightServerStartTests.swift
//  HomeAutomationKitTests
//

import Foundation
import HAApplicationLayer
import HAImplementations
import HAModels
import Testing

/// After a server start, motion that is still held switches the light on again, as the adapter's
/// resync did before a replay stopped counting as a change.
@HomeManagerActor
@Suite("MotionAtNight after a server start", .timeLimit(.minutes(1)))
struct MotionAtNightServerStartTests {
    private let motion = EveMotion(query: .init(placeId: "Kueche", name: "Motion"))
    private let light = LightBulbDimmable(query: .init(placeId: "Kueche", name: "Light"))
    private let homeManager = MockHomeAdapter()
    private let runs = InMemoryAutomationRunRepository()

    @Test("a server start with motion in the dark runs the normal sequence and names the server start")
    func serverStartRunsTheNormalSequence() async throws {
        let lightSensorId = try #require(motion.lightSensorId)
        homeManager.storageItems = [
            EntityStorageItem(entityId: lightSensorId, illuminance: .init(value: 5, unit: .lux)),
            EntityStorageItem(entityId: motion.motionSensorId, motionDetected: true),
            EntityStorageItem(entityId: light.switchId, isDeviceOn: false)
        ]
        let automation = MotionAtNight("motion-at-night", colorTemperatureDelay: .zero, motionSensors: [motion], lightSensor: motion, lights: [light], minBrightness: 0.1)
        let service = try AutomationService(using: homeManager, runs: runs, getAutomations: { @Sendable in [automation] })

        await service.trigger(with: .serverStarted)

        // the light goes on first, then the run waits for the held motion to end
        let brightnessId = try #require(light.brightnessId)
        for await action in homeManager.performedActionStream {
            if case .setBrightness(brightnessId, _) = action { break }
        }
        await service.stopAutomation(with: "motion-at-night")
        let run = try #require(await runs.nextFinishedRun())
        #expect(run.trigger.kind == .serverStart)
        #expect(run.trigger.summary == "Server started · at 5 lx")
    }
}
