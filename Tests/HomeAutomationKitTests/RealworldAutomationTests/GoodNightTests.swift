import Foundation
@testable import HAApplicationLayer
@testable import HAImplementations
import HAModels
import Testing

@HomeManagerActor
struct GoodNightTests {
    let noMotionWait: Duration = .milliseconds(200)
    let dimWait: Duration = .milliseconds(50)
    let deviceEveMotion = EveMotion(query: .init(placeId: "room1", name: "motion1"))
    let deviceEveMotion2 = EveMotion(query: .init(placeId: "room2", name: "motion2", characteristicsName: "characteristicName2"))
    let automation: GoodNight
    init() {
        automation = GoodNight("good-night",
                               at: Time(hour: 0, minute: 0),
                               motionSensors: [deviceEveMotion, deviceEveMotion2],
                               motionWait: .milliseconds(100))
    }

    @Test("Motion trigger without wait", .tags(.localOnly))
    func triggerWithoutWait() async throws {
        // prepare

        // run
        let mockHomeAdapter = MockHomeAdapter()
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
        let homeManager = HomeManager(getAdapter: {
            return nil
        }, storageRepo: mockStorageRepo, location: Location(latitude: 1, longitude: 2))

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
        let mockHomeAdapter = MockHomeAdapter()
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
        let homeManager = HomeManager(getAdapter: {
            return nil
        }, storageRepo: mockStorageRepo, location: Location(latitude: 1, longitude: 2))

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
