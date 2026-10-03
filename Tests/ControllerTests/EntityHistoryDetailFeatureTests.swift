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
}
