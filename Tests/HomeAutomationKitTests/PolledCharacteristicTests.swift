//
//  PolledCharacteristicTests.swift
//  HomeAutomationKitTests
//

import Foundation
@testable import HAApplicationLayer
@testable import HAModels
import Testing

/// Battery level, temperature and humidity are read actively by the adapter (on every resync and every few hours),
/// because HomeKit notifications for them are unreliable or, for the battery, deliberately not subscribed.
struct PolledCharacteristicTests {
    private let battery = EntityId(placeId: "room", name: "sensor", characteristicsName: nil, characteristic: .batterySensor)
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Exactly battery level, temperature and humidity are polled")
    func polledTypes() {
        let polled = Set(CharacteristicsType.allCases.filter(\.isPolled))
        #expect(polled == [.batterySensor, .temperatureSensor, .relativeHumiditySensor])
    }

    @Test("The battery stays unsubscribed, but its reads reach the server")
    func batteryIsPolledNotSubscribed() {
        #expect(!CharacteristicsType.batterySensor.isSubscribed)
        #expect(CharacteristicsType.batterySensor.isReported)
    }

    @Test("Every subscribed type is reported; others only when polled", arguments: CharacteristicsType.allCases)
    func reportedIsSubscribedOrPolled(type: CharacteristicsType) {
        #expect(type.isReported == (type.isSubscribed || type.isPolled))
    }

    @Test("The poll runs every three hours")
    func pollInterval() {
        #expect(CharacteristicsType.pollInterval == .seconds(3 * 3600))
    }

    @Test("A polled battery level that did not change stores no new row, only the report time")
    func unchangedPollStoresNoRow() async throws {
        let storage = MockStorageRepository()
        let clock = TestClock(start)
        let manager = await HomeManager(getAdapter: { nil },
                                        storageRepo: storage,
                                        notificationSender: MockNotificationSender(),
                                        location: Location(latitude: 0, longitude: 0),
                                        retryTicks: AsyncStream { _ in },
                                        persistRetryDelays: [.zero],
                                        now: { clock.date })
        let first = try #require(EntityStorageItem(entityId: battery, timestamp: start, value: .number(80)))
        #expect(await manager.addEntityHistory(first))
        await eventually("the first level is stored") { storage.items.contains { $0.entityId == battery } }

        let later = start.addingTimeInterval(3 * 3600)
        clock.date = later
        let poll = try #require(EntityStorageItem(entityId: battery, timestamp: later, value: .number(80)))
        #expect(await manager.addEntityHistory(poll) == false)

        #expect(storage.items.filter { $0.entityId == battery }.count == 1)
        #expect(await manager.lastReport(of: battery) == later)
    }
}
