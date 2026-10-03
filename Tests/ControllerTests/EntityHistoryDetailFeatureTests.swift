//
//  EntityHistoryDetailFeatureTests.swift
//  ControllerTests
//

import ComposableArchitecture
@testable import Controller
import Foundation
import HAModels
import Testing

@MainActor
@Suite("EntityHistoryDetailFeature")
struct EntityHistoryDetailFeatureTests {
    private let entity = EntityInfo(entityId: EntityId(placeId: "Bath", name: "Sensor", characteristicsName: nil, characteristic: .temperatureSensor))

    /// Paging through actions let a late page reach a screen that was already popped (TCA
    /// "missing element" warning); every page has to arrive from one effect.
    @Test("refresh loads every page from one effect")
    func refreshLoadsAllPages() async {
        let first = EntityHistoryItem(timestamp: Date(timeIntervalSince1970: 10), temperatureInC: 21)
        let second = EntityHistoryItem(timestamp: Date(timeIntervalSince1970: 5), temperatureInC: 20)
        let store = TestStore(initialState: EntityHistoryDetailFeature.State(entity: entity)) {
            EntityHistoryDetailFeature()
        } withDependencies: {
            $0.serverClient.getEntityHistory = { _, _, _, cursor, _, _ in
                if cursor == nil {
                    return EntityHistoryResponse(items: [first], nextCursor: first.timestamp)
                }
                return EntityHistoryResponse(items: [second], nextCursor: nil)
            }
        }

        await store.send(.refresh) {
            $0.isLoading = true
        }
        await store.receive(\.historyResponse.success) {
            $0.isLoading = false
            $0.historyItems = [first]
        }
        await store.receive(\.historyResponse.success) {
            $0.historyItems = [first, second]
        }
    }

    @Test("changing the time range reloads from scratch")
    func timeRangeReloads() async {
        let store = TestStore(initialState: EntityHistoryDetailFeature.State(entity: entity)) {
            EntityHistoryDetailFeature()
        }

        await store.send(.timeRangeChanged(.week)) {
            $0.timeRange = .week
        }
        await store.receive(\.refresh) {
            $0.isLoading = true
        }
        await store.receive(\.historyResponse.success) {
            $0.isLoading = false
        }
    }

    @Test("a failed load shows an alert")
    func failureShowsAlert() async {
        struct LoadError: Error {}
        let store = TestStore(initialState: EntityHistoryDetailFeature.State(entity: entity)) {
            EntityHistoryDetailFeature()
        } withDependencies: {
            $0.serverClient.getEntityHistory = { _, _, _, _, _, _ in throw LoadError() }
        }

        await store.send(.refresh) {
            $0.isLoading = true
        }
        await store.receive(\.historyResponse.failure) {
            $0.isLoading = false
            $0.alert = AlertState {
                TextState("Error")
            } actions: {
                ButtonState(action: .dismissError) {
                    TextState("OK")
                }
            } message: {
                TextState("Failed to load history: \(LoadError().localizedDescription)")
            }
        }
    }
}
