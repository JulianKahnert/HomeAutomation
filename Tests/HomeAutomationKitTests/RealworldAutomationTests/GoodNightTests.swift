import Foundation
@testable import HAApplicationLayer
@testable import HAConfig
@testable import HAImplementations
@testable import HomeAutomationKit
import Testing

@HomeManagerActor
struct GoodNightTests {
    let noMotionWait: Duration = .milliseconds(200)
    let dimWait: Duration = .milliseconds(50)
    let deviceEveMotion = EveMotion(query: .init(placeId: "room1", name: "motion1"))
    let deviceEveMotion2 = EveMotion(query: .init(placeId: "room2", name: "motion2", characteristicsName: "characteristicName2"))
    let automation: GoodNight
    let config: Config
    init() {
        automation = GoodNight(at: Time(hour: 0, minute: 0),
                               motionSensors: [deviceEveMotion, deviceEveMotion2],
                               motionWait: .milliseconds(100))
        config = Config(automations: [automation],
                        location: .oldenburgLocation,
                        devices: [deviceEveMotion, deviceEveMotion2])
    }

    @Test("Motion trigger without wait", .tags(.localOnly))
    func triggerWithoutWait() async throws {
        // prepare

        // run
        let mockHomeAdapter = MockHomeAdapter(with: config)
        mockHomeAdapter.storageItems = [
            EntityStorageItem(entityId: deviceEveMotion.motionSensorId,
                              timestamp: Date(),
                              motionDetected: false,
                              illuminance: nil,
                              isDeviceOn: nil,
                              isContactOpen: nil,
                              isDoorLocked: nil,
                              stateOfCharge: nil,
                              isHeaterActive: nil),
            EntityStorageItem(entityId: deviceEveMotion2.motionSensorId,
                              timestamp: Date(),
                              motionDetected: false,
                              illuminance: nil,
                              isDeviceOn: nil,
                              isContactOpen: nil,
                              isDoorLocked: nil,
                              stateOfCharge: nil,
                              isHeaterActive: nil)
        ]

        let mockStorageRepo = MockStorageRepository(items: mockHomeAdapter.storageItems)
        let homeManager = HomeManager(with: mockHomeAdapter, storageRepo: mockStorageRepo, config: config)

        // trigger motion
        let start = Date()
        try await automation.execute(using: homeManager)
        let end = Date()

        // assert
        #expect(end.timeIntervalSince(start) < 0.05)
    }

    @Test("Motion trigger with wait", .tags(.localOnly))
    func triggerWithWait() async throws {
        // prepare

        // run
        let mockHomeAdapter = MockHomeAdapter(with: config)
        mockHomeAdapter.storageItems = [
            EntityStorageItem(entityId: deviceEveMotion.motionSensorId,
                              timestamp: Date(),
                              motionDetected: false,
                              illuminance: nil,
                              isDeviceOn: nil,
                              isContactOpen: nil,
                              isDoorLocked: nil,
                              stateOfCharge: nil,
                              isHeaterActive: nil),
            EntityStorageItem(entityId: deviceEveMotion2.motionSensorId,
                              timestamp: Date(),
                              motionDetected: true,
                              illuminance: nil,
                              isDeviceOn: nil,
                              isContactOpen: nil,
                              isDoorLocked: nil,
                              stateOfCharge: nil,
                              isHeaterActive: nil)
        ]

        let mockStorageRepo = MockStorageRepository(items: mockHomeAdapter.storageItems)
        let homeManager = HomeManager(with: mockHomeAdapter, storageRepo: mockStorageRepo, config: config)

        // trigger motion
        let start = Date()
        try await automation.execute(using: homeManager)
        let end = Date()

        // assert
        print(end.timeIntervalSince(start))
        print(end.timeIntervalSince(start))
        #expect(end.timeIntervalSince(start) < 0.6)
    }
}
