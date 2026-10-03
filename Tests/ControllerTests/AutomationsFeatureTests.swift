//
//  AutomationsFeatureTests.swift
//  ControllerTests
//

import ComposableArchitecture
@testable import Controller
import Foundation
import HAModels
import Testing

@MainActor
@Suite("AutomationsFeature")
struct AutomationsFeatureTests {
    struct ActivateError: Error {}

    private let automations: IdentifiedArrayOf<AutomationInfo> = [
        AutomationInfo(name: "Evening", isActive: true, isRunning: false, type: "Turn"),
        AutomationInfo(name: "Hallway", isActive: true, isRunning: true, type: "MotionAtNight"),
        AutomationInfo(name: "Vacation", isActive: false, isRunning: false, type: "TriggerScene")
    ]

    @Test("status grouping splits active and inactive, running first")
    func groupsByStatus() {
        let state = AutomationsFeature.State()
        state.$automations.withLock { $0 = automations }
        state.$grouping.withLock { $0 = .status }

        #expect(state.sections.map(\.title) == ["Active", "Inactive"])
        #expect(state.sections[0].automations.map(\.name) == ["Hallway", "Evening"])
    }

    @Test("type grouping uses the type label")
    func groupsByType() {
        let state = AutomationsFeature.State()
        state.$automations.withLock { $0 = automations }
        state.$grouping.withLock { $0 = .type }

        #expect(state.sections.map(\.title) == ["Motion", "Scene", "Schedule"])
    }

    @Test("toggle is applied optimistically and rolled back on failure")
    func toggleRollsBack() async {
        let store = TestStore(initialState: AutomationsFeature.State()) {
            AutomationsFeature()
        } withDependencies: {
            $0.serverClient.deactivate = { _ in throw ActivateError() }
        }
        store.state.$automations.withLock { $0 = automations }

        await store.send(.setActive(name: "Evening", false)) {
            $0.$automations.withLock { $0[id: "Evening"]?.isActive = false }
        }
        await store.receive(\.setActiveResponse) {
            $0.$automations.withLock { $0[id: "Evening"]?.isActive = true }
            $0.alert = AlertState {
                TextState("Error")
            } actions: {
                ButtonState(action: .dismissError) {
                    TextState("OK")
                }
            } message: {
                TextState("Failed to change Evening: \(ActivateError().localizedDescription)")
            }
        }
    }
}

@Suite("RoomsFeature")
struct RoomsFeatureTests {
    private let entities = [
        EntityInfo.preview(placeId: "Kitchen", name: "Ceiling"),
        EntityInfo.preview(placeId: "Kitchen", name: "Window", type: .contactSensor),
        EntityInfo.preview(placeId: "Bath", name: "Mirror")
    ]

    @Test("rooms are listed alphabetically with all their devices")
    func roomsGroupDevices() {
        var state = RoomsFeature.State()
        state.entities = entities

        #expect(state.rooms.map(\.placeId) == ["Bath", "Kitchen"])
        #expect(state.rooms[1].entities.map(\.entityId.name) == ["Ceiling", "Window"])
    }

    @Test("search matches room names and device names, keeping the whole room")
    func searchKeepsWholeRoom() {
        var state = RoomsFeature.State()
        state.entities = entities

        state.searchText = "window"
        #expect(state.rooms.map(\.placeId) == ["Kitchen"])
        #expect(state.rooms[0].entities.count == 2)

        state.searchText = "bath"
        #expect(state.rooms.map(\.placeId) == ["Bath"])
    }
}

@Suite("ActionsFeature")
struct ActionsFeatureTests {
    @Test("command log filter matches status, falling back to the cache flag for old servers")
    func filterMatchesStatus() {
        let entityId = EntityId(placeId: "Hall", name: "Light", characteristicsName: nil, characteristic: .switcher)
        func item(_ status: ActionLogItem.Status?, cached: Bool = false) -> ActionLogItem {
            ActionLogItem(
                id: UUID(),
                timestamp: Date(),
                entityId: entityId,
                actionName: "on",
                detailDescription: "turnOn",
                hasCacheHit: cached,
                status: status
            )
        }

        #expect(ActionsFeature.Filter.fresh.matches(item(nil)))
        #expect(ActionsFeature.Filter.cache.matches(item(.cacheHit, cached: true)))
        #expect(ActionsFeature.Filter.failed.matches(item(.failed)))
        #expect(!ActionsFeature.Filter.fresh.matches(item(.failed)))
    }
}
