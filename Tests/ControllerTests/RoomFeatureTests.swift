//
//  RoomFeatureTests.swift
//  ControllerTests
//

import ComposableArchitecture
@testable import Controller
import Foundation
import HAModels
import Synchronization
import Testing

@MainActor
@Suite("RoomFeature")
struct RoomFeatureTests {
    private let ceiling = EntityInfo.preview(placeId: "Kitchen", name: "Ceiling")
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test("only automations with a device in the room are kept")
    func automationsFilteredToRoom() async {
        let kitchen = AutomationInfo(name: "Kitchen Light", isActive: true, isRunning: false, entities: [ceiling.entityId])
        let hall = AutomationInfo(name: "Hall Light", isActive: true, isRunning: false, entities: [EntityInfo.preview(placeId: "Hall").entityId])
        let store = TestStore(initialState: RoomFeature.State(placeId: "Kitchen", entities: [ceiling])) {
            RoomFeature()
        } withDependencies: {
            $0.date.now = now
            $0.serverClient.getAutomations = { [kitchen, hall] }
        }
        store.exhaustivity = .off

        await store.send(.task)
        await store.receive(\.automationsResponse.success) {
            $0.automations = [kitchen]
        }
    }

    @Test("changing the time range reloads the room history for that range")
    func timeRangeReloadsHistory() async {
        let requestedStarts = Mutex<[Date?]>([])
        let store = TestStore(initialState: RoomFeature.State(placeId: "Kitchen", entities: [ceiling])) {
            RoomFeature()
        } withDependencies: {
            $0.date.now = now
            $0.serverClient.getRoomHistory = { _, start, _, _ in
                requestedStarts.withLock { $0.append(start) }
                return []
            }
        }

        await store.send(.binding(.set(\.timeRange, .hour))) {
            $0.timeRange = .hour
            $0.end = now
        }
        await store.receive(\.historyResponse.success)

        #expect(requestedStarts.withLock { $0 } == [now.addingTimeInterval(-3_600)])
    }

    @Test("a failed history load is shown as error")
    func failureSetsError() async {
        struct LoadError: Error {}
        let store = TestStore(initialState: RoomFeature.State(placeId: "Kitchen", entities: [ceiling])) {
            RoomFeature()
        } withDependencies: {
            $0.date.now = now
            $0.serverClient.getRoomHistory = { _, _, _, _ in throw LoadError() }
        }
        store.exhaustivity = .off

        await store.send(.task)
        await store.receive(\.historyResponse.failure) {
            $0.error = LoadError().localizedDescription
        }
    }
}
