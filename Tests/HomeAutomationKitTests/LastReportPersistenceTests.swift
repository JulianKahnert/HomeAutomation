//
//  LastReportPersistenceTests.swift
//  HomeAutomationKitTests
//

import Foundation
@testable import HAApplicationLayer
@testable import HAModels
import Synchronization
import Testing

/// T27: the time of the last report is stored, on a change with the change and otherwise at most every five minutes
/// per entity; a restart loads it.
struct LastReportPersistenceTests {
    private let lamp = EntityId(placeId: "room", name: "lamp", characteristicsName: nil, characteristic: .switcher)
    private let other = EntityId(placeId: "room", name: "other", characteristicsName: nil, characteristic: .switcher)
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeManager(storage: MockStorageRepository, clock: TestClock) async -> HomeManager {
        await HomeManager(getAdapter: { nil },
                          storageRepo: storage,
                          notificationSender: MockNotificationSender(),
                          location: Location(latitude: 0, longitude: 0),
                          retryTicks: AsyncStream { _ in },
                          persistRetryDelays: [.zero],
                          now: { clock.date })
    }

    /// The persist queue is in order: once a change of another entity is stored, everything queued before it was handled.
    private func flush(_ manager: HomeManager, storage: MockStorageRepository) async {
        let marker = EntityStorageItem(entityId: other, timestamp: .now, isDeviceOn: storage.items.count.isMultiple(of: 2))
        await manager.addEntityHistory(marker)
        let count = storage.items.count
        await eventually("the marker is stored") { storage.items.count > count || storage.items.contains { $0.entityId == other && $0.timestamp == marker.timestamp } }
    }

    @Test("A change is stored with the time of its report; an unchanged report within five minutes writes nothing")
    func changeCarriesTheReportAndReplaysAreThrottled() async throws {
        let storage = MockStorageRepository()
        let clock = TestClock(start)
        let manager = await makeManager(storage: storage, clock: clock)

        await manager.addEntityHistory(EntityStorageItem(entityId: lamp, timestamp: start, isDeviceOn: true))
        for seconds in [60.0, 150, 299] {
            clock.date = start.addingTimeInterval(seconds)
            await manager.addEntityHistory(EntityStorageItem(entityId: lamp, timestamp: start.addingTimeInterval(seconds), isDeviceOn: true))
        }
        await eventually("the change is stored") { storage.items.contains { $0.entityId == lamp } }
        await flush(manager, storage: storage)

        #expect(storage.items.first { $0.entityId == lamp }?.lastReport == start)
        #expect(storage.lastReportWrites.isEmpty)
    }

    @Test("The first unchanged report after five minutes is written, then the interval starts again")
    func aReplayAfterFiveMinutesIsWrittenOncePerInterval() async throws {
        let storage = MockStorageRepository()
        let clock = TestClock(start)
        let manager = await makeManager(storage: storage, clock: clock)
        await manager.addEntityHistory(EntityStorageItem(entityId: lamp, timestamp: start, isDeviceOn: true))

        for seconds in [301.0, 400, 600, 602, 700] {
            let date = start.addingTimeInterval(seconds)
            clock.date = date
            await manager.addEntityHistory(EntityStorageItem(entityId: lamp, timestamp: date, isDeviceOn: true))
        }
        await flush(manager, storage: storage)

        // 301 s writes; 400 and 600 are within five minutes of it; 602 writes; 700 is within
        #expect(storage.lastReportWrites.map(\.date) == [start.addingTimeInterval(301), start.addingTimeInterval(602)])
        #expect(await manager.lastReport(of: lamp) == start.addingTimeInterval(700))
    }

    @Test("A restart loads the stored time and does not write again within the interval")
    func aRestartLoadsTheLastReport() async throws {
        let stored = EntityStorageItem(entityId: lamp, timestamp: start, isDeviceOn: true, lastReport: start.addingTimeInterval(100))
        let storage = MockStorageRepository(items: [stored])
        let clock = TestClock(start.addingTimeInterval(200))
        let manager = await makeManager(storage: storage, clock: clock)
        await manager.loadCurrentStates(timeout: .seconds(5))

        #expect(await manager.lastReport(of: lamp) == start.addingTimeInterval(100))

        // a replay 100 s after the stored report: refreshes the time in memory, writes nothing
        await manager.addEntityHistory(EntityStorageItem(entityId: lamp, timestamp: clock.date, isDeviceOn: true))
        await flush(manager, storage: storage)
        #expect(await manager.lastReport(of: lamp) == start.addingTimeInterval(200))
        #expect(storage.lastReportWrites.isEmpty)
    }
}

/// A clock the test moves by hand.
final class TestClock: Sendable {
    private let current: Mutex<Date>

    init(_ date: Date) { current = Mutex(date) }

    var date: Date {
        get { current.withLock { $0 } }
        set { current.withLock { $0 = newValue } }
    }
}
