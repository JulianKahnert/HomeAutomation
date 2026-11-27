//
//  ShouldTriggerMemoryTests.swift
//  HomeAutomationKitTests
//

import Foundation
@testable import HAApplicationLayer
@testable import HAImplementations
import HAModels
import Testing

/// Whether the code running is a decision; the background save of a change reads the database on its own task.
private enum Decision {
    @TaskLocal static var isRunning = false
}

/// Every repository answers while the server starts and counts the reads a decision makes after it; it must make none.
private actor Repositories: StorageRepository, HeatingWriteRepository, FireplaceRepository {
    private(set) var callsAfterStart = 0
    private var blocked = false
    private let radiatorWrite: HeatingWrite?

    init(radiatorWrite: HeatingWrite? = nil) {
        self.radiatorWrite = radiatorWrite
    }

    func block() { blocked = true }
    private func touch() { if blocked, Decision.isRunning { callsAfterStart += 1 } }

    func getCurrent(_ entityId: EntityId) async throws -> EntityStorageItem? { touch(); return nil }
    func getPrevious(_ entityId: EntityId) async throws -> EntityStorageItem? { touch(); return nil }
    func getAllCurrent() async throws -> [EntityStorageItem] { touch(); return [] }
    func add(_ item: EntityStorageItem) async throws {} // the background save of a change is no read
    func getHistory(for entityId: EntityId, startDate: Date?, endDate: Date?, cursor: Date?, limit: Int) async throws -> [EntityStorageItem] { touch(); return [] }

    func getAllEntityIds() async throws -> [EntityId] { touch(); return [] }

    func add(_ write: HeatingWrite) async throws { touch() }
    func writes(placeId: String, startDate: Date?, endDate: Date?) async throws -> [HeatingWrite] { touch(); return [] }
    func lastPlanWrite(placeId: String, before date: Date) async throws -> HeatingWrite? { touch(); return nil }
    func lastWrite(placeId: String, radiatorName: String) async throws -> HeatingWrite? { touch(); return nil }
    func lastWrites() async throws -> [HeatingWrite] { touch(); return radiatorWrite.map { [$0] } ?? [] }

    func add(_ fireplaceSwitch: FireplaceSwitch) async throws { touch() }
    func latest() async throws -> FireplaceSwitch? { touch(); return nil }
    func switches(from startDate: Date, to endDate: Date) async throws -> [FireplaceSwitch] { touch(); return [] }
}

@Suite("shouldTrigger reads memory only")
@HomeManagerActor
struct ShouldTriggerMemoryTests {
    private let radiator = Radiator(query: .init(placeId: "Kitchen", name: "Left"))
    private let window = WindowContactSensor(query: .init(placeId: "Kitchen", name: "Window"))
    private let motion = EveMotion(query: .init(placeId: "Kueche", name: "Motion"))
    private let light = LightBulbDimmable(query: .init(placeId: "Kueche", name: "Light"))
    private let roomSensor = EntityId(placeId: "Keller", name: "Raumsensor", characteristicsName: nil, characteristic: .temperatureSensor)
    private let now = Date()

    private func makeHomeManager(_ repositories: Repositories) async -> HomeManager {
        await HomeManager(getAdapter: { nil },
                          storageRepo: repositories,
                          notificationSender: MockNotificationSender(),
                          location: Location(latitude: 0, longitude: 0),
                          heatingWrites: repositories,
                          fireplaceSwitches: repositories,
                          retryTicks: AsyncStream { _ in })
    }

    private func automations() -> [any Automatable] {
        [RoomHeating("heating",
                     placeId: "Kitchen",
                     radiators: [radiator],
                     contacts: [.window(window), .fireplace()],
                     configuration: HeatingConfiguration(standardPlan: HeatingPlan([]))),
         FireplaceReminder(roomSensor: roomSensor),
         MotionAtNight("motion", motionSensors: [motion], lightSensor: motion, lights: [light], minBrightness: 0.1),
         DatabaseCleanup()]
    }

    @Test("No automation reaches a repository while deciding")
    func noRepositoryCall() async throws {
        let repositories = Repositories()
        let homeManager = await makeHomeManager(repositories)
        await homeManager.loadCurrentStates(timeout: .seconds(2))
        await repositories.block()

        let reading = EntityStorageItem(entityId: roomSensor, timestamp: now, temperatureInC: Measurement(value: 20, unit: .celsius))
        let closed = EntityStorageItem(entityId: window.contactSensorId, isContactOpen: false)
        let moving = EntityStorageItem(entityId: motion.motionSensorId, motionDetected: true)
        let events: [HomeEvent] = [.change(entity: reading), .change(entity: closed), .change(entity: moving), .serverStarted,
                                   .time(date: now), .fireplaceChanged(isOn: false), .fireplaceChanged(isOn: true), .sunset]
        for event in events { await homeManager.addEntityHistory(event.item) }
        for automation in automations() {
            for event in events {
                _ = try? await Decision.$isRunning.withValue(true) { try await automation.shouldTrigger(with: event, using: homeManager) }
            }
        }

        #expect(await repositories.callsAfterStart == 0)
    }

    @Test("With the storage blocked a motion event still triggers at once")
    func motionTriggersWithoutStorage() async throws {
        let repositories = Repositories()
        let homeManager = await makeHomeManager(repositories)
        await homeManager.loadCurrentStates(timeout: .seconds(2))
        await repositories.block()
        await homeManager.addEntityHistory(EntityStorageItem(entityId: EntityId(query: .init(placeId: "Kueche", name: "Motion"), characteristic: .lightSensor),
                                                             illuminance: .init(value: 5, unit: .lux)))
        let moving = EntityStorageItem(entityId: motion.motionSensorId, motionDetected: true)
        await homeManager.addEntityHistory(moving)

        let automation = MotionAtNight("motion", motionSensors: [motion], lightSensor: motion, lights: [light], minBrightness: 0.1)

        let triggers = try await Decision.$isRunning.withValue(true) { try await automation.shouldTrigger(with: .change(entity: moving), using: homeManager) }
        #expect(triggers)
        #expect(await repositories.callsAfterStart == 0)
    }

    @Test("The last command per radiator is loaded at start and follows the commands since")
    func lastCommandPerRadiator() async throws {
        let earlier = HeatingWrite(timestamp: now.addingTimeInterval(-600), entityId: radiator.heatingId, reason: .window, actionName: "setHeating", isActive: false)
        let repositories = Repositories(radiatorWrite: earlier)
        let homeManager = await makeHomeManager(repositories)
        await homeManager.loadCurrentStates(timeout: .seconds(2))
        await repositories.block()

        #expect(await homeManager.lastHeatingWrite(of: radiator.heatingId) == earlier)

        let later = HeatingWrite(timestamp: now, entityId: radiator.heatingId, reason: .plan, actionName: "setHeating", isActive: true)
        await homeManager.record(later)
        #expect(await homeManager.lastHeatingWrite(of: radiator.heatingId) == later)
    }

    @Test("The readings of the window survive a restart")
    func readingsLoadedAtStart() async throws {
        let stored = MockStorageRepository(items: [
            EntityStorageItem(entityId: roomSensor, timestamp: Date().addingTimeInterval(-25 * 60), temperatureInC: Measurement(value: 18, unit: .celsius)),
            EntityStorageItem(entityId: roomSensor, timestamp: Date().addingTimeInterval(-60), temperatureInC: Measurement(value: 19.5, unit: .celsius))
        ])
        let homeManager = await HomeManager(getAdapter: { nil },
                                            storageRepo: stored,
                                            notificationSender: MockNotificationSender(),
                                            location: Location(latitude: 0, longitude: 0),
                                            retryTicks: AsyncStream { _ in })
        await homeManager.loadCurrentStates(timeout: .seconds(2))

        let history = await homeManager.getEntityHistory(with: roomSensor, since: Date().addingTimeInterval(-30 * 60))

        #expect(history.compactMap { $0.temperatureInC?.value } == [19.5, 18])
    }

    @Test("The readings of the window are available from memory, newest first")
    func readingsFromMemory() async throws {
        let repositories = Repositories()
        let homeManager = await makeHomeManager(repositories)
        await homeManager.loadCurrentStates(timeout: .seconds(2))
        await repositories.block()
        for (value, minutesAgo) in [(18.0, 50.0), (18.5, 20.0), (19.2, 0.0)] {
            let reading = EntityStorageItem(entityId: roomSensor,
                                            timestamp: now.addingTimeInterval(-minutesAgo * 60),
                                            temperatureInC: Measurement(value: value, unit: .celsius))
            await homeManager.addEntityHistory(reading)
        }

        let history = await Decision.$isRunning.withValue(true) { await homeManager.getEntityHistory(with: roomSensor, since: now.addingTimeInterval(-30 * 60)) }

        #expect(history.compactMap { $0.temperatureInC?.value } == [19.2, 18.5])
        #expect(await repositories.callsAfterStart == 0)
    }
}

private extension HomeEvent {
    var item: EntityStorageItem {
        if case .change(let item) = self { return item }
        return EntityStorageItem(entityId: Fireplace.stateId)
    }
}
