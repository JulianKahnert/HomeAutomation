//
//  RoomHistoryTests.swift
//  HomeAutomationKit
//

import Foundation
import HAModels
import Testing

/// Covers the `StorageRepository` extension the server uses for `/entities/history/room`.
struct RoomHistoryTests {
    private let light = EntityId(placeId: "Kitchen", name: "Worklight", characteristicsName: nil, characteristic: .switcher)
    private let window = EntityId(placeId: "Kitchen", name: "Window", characteristicsName: nil, characteristic: .contactSensor)
    private let hallway = EntityId(placeId: "Hallway", name: "Light", characteristicsName: nil, characteristic: .switcher)
    private let start = Date(timeIntervalSince1970: 10_000)

    private func item(_ entityId: EntityId, at offset: TimeInterval, isOn: Bool = true) -> EntityStorageItem {
        EntityStorageItem(entityId: entityId, timestamp: start.addingTimeInterval(offset), isDeviceOn: isOn)
    }

    @Test func returnsEveryEntityOfThePlaceOnly() async throws {
        let repository = MockStorageRepository(items: [item(light, at: 10), item(window, at: 20), item(hallway, at: 30)])

        let history = try await repository.getRoomHistory(placeId: "Kitchen", startDate: start, endDate: nil, includePrevious: false)

        #expect(Set(history.map(\.entityId)) == [light, window])
    }

    @Test func includePreviousAppendsTheStateBeforeTheWindow() async throws {
        let repository = MockStorageRepository(items: [item(light, at: -7_200, isOn: false), item(light, at: -3_600), item(light, at: 60, isOn: false)])

        let history = try await repository.getRoomHistory(placeId: "Kitchen", startDate: start, endDate: nil, includePrevious: true)

        let timestamps = try #require(history.first).items.map(\.timestamp)
        #expect(timestamps == [start.addingTimeInterval(60), start.addingTimeInterval(-3_600)])
    }

    @Test func withoutIncludePreviousTheWindowIsExact() async throws {
        let repository = MockStorageRepository(items: [item(light, at: -3_600), item(light, at: 60)])

        let items = try await repository.getHistory(for: light, startDate: start, endDate: nil, cursor: nil, limit: 100, includePrevious: false)

        #expect(items.map(\.timestamp) == [start.addingTimeInterval(60)])
    }

    @Test func includePreviousIsSkippedWhileMorePagesFollow() async throws {
        let repository = MockStorageRepository(items: [item(light, at: -3_600), item(light, at: 60), item(light, at: 120)])

        let items = try await repository.getHistory(for: light, startDate: start, endDate: nil, cursor: nil, limit: 2, includePrevious: true)

        #expect(items.count == 2)
    }
}
