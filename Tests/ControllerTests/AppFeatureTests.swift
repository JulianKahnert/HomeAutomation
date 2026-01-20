//
//  AppFeatureTests.swift
//  ControllerFeaturesTests
//
//  Tests for AppFeature scene phase change handling
//

import ComposableArchitecture
@testable import Controller
import Dependencies
import HAModels
import Testing

@Suite("AppFeature Tests")
struct AppFeatureTests {

    @Test("scenePhaseChanged from inactive to active dispatches refresh to all child features")
    @MainActor
    func testScenePhaseChangedInactiveToActive() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.serverClient = .testValue
            $0.liveActivity = .testValue
            $0.pushNotification = .testValue
        }

        // Send the scene change action for inactive -> active transition
        await store.send(.scenePhaseChanged(old: .inactive, new: .active))

        // Verify that refresh actions are dispatched to all child features
        // Note: Actions may arrive in any order due to parallel execution via .merge()
        await store.receive(\.automations.refresh) { state in
            state.automations.isLoading = true
            state.automations.error = nil
        }

        await store.receive(\.actions.refresh) { state in
            state.actions.isLoading = true
            state.actions.alert = nil
        }

        await store.receive(\.history.refresh) { state in
            state.history.isLoading = true
            state.history.alert = nil
        }

        await store.receive(\.refreshWindowStates)

        await store.receive(\.startMonitoringLiveActivities)

        await store.receive(\.clearDeliveredNotifications)

        await store.receive(\.settings.refreshWindowStates) { state in
            state.settings.isLoadingWindowStates = true
            state.settings.error = nil
        }

        // Verify that the refresh operations complete
        // History response comes first because it's synchronous
        await store.receive(\.history.entitiesResponse) { state in
            state.history.isLoading = false
            state.history.entities = []
        }

        await store.receive(\.automations.automationsResponse) { state in
            state.automations.isLoading = false
        }

        await store.receive(\.actions.actionsResponse) { state in
            state.actions.isLoading = false
        }

        await store.receive(\.settings.windowStatesResponse) { state in
            state.settings.isLoadingWindowStates = false
            state.settings.windowContentState = WindowContentState(windowStates: [])
        }
    }

    @Test("scenePhaseChanged from background to active dispatches refresh to all child features")
    @MainActor
    func testScenePhaseChangedBackgroundToActive() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.serverClient = .testValue
            $0.liveActivity = .testValue
            $0.pushNotification = .testValue
        }

        // Send the scene change action for background -> active transition
        await store.send(.scenePhaseChanged(old: .background, new: .active))

        // Verify that refresh actions are dispatched to all child features
        await store.receive(\.automations.refresh) { state in
            state.automations.isLoading = true
            state.automations.error = nil
        }

        await store.receive(\.actions.refresh) { state in
            state.actions.isLoading = true
            state.actions.alert = nil
        }

        await store.receive(\.history.refresh) { state in
            state.history.isLoading = true
            state.history.alert = nil
        }

        await store.receive(\.refreshWindowStates)

        await store.receive(\.startMonitoringLiveActivities)

        await store.receive(\.clearDeliveredNotifications)

        await store.receive(\.settings.refreshWindowStates) { state in
            state.settings.isLoadingWindowStates = true
            state.settings.error = nil
        }

        // Verify that the refresh operations complete
        await store.receive(\.history.entitiesResponse) { state in
            state.history.isLoading = false
            state.history.entities = []
        }

        await store.receive(\.automations.automationsResponse) { state in
            state.automations.isLoading = false
        }

        await store.receive(\.actions.actionsResponse) { state in
            state.actions.isLoading = false
        }

        await store.receive(\.settings.windowStatesResponse) { state in
            state.settings.isLoadingWindowStates = false
            state.settings.windowContentState = WindowContentState(windowStates: [])
        }
    }

    @Test("scenePhaseChanged refreshes run in parallel")
    @MainActor
    func testParallelRefresh() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.serverClient = .testValue
            $0.liveActivity = .testValue
            $0.pushNotification = .testValue
        }

        // Send the scene change action
        await store.send(.scenePhaseChanged(old: .background, new: .active))

        // All refresh actions should be dispatched
        await store.receive(\.automations.refresh) { state in
            state.automations.isLoading = true
            state.automations.error = nil
        }

        await store.receive(\.actions.refresh) { state in
            state.actions.isLoading = true
            state.actions.alert = nil
        }

        await store.receive(\.history.refresh) { state in
            state.history.isLoading = true
            state.history.alert = nil
        }

        await store.receive(\.refreshWindowStates)

        await store.receive(\.startMonitoringLiveActivities)

        await store.receive(\.clearDeliveredNotifications)

        await store.receive(\.settings.refreshWindowStates) { state in
            state.settings.isLoadingWindowStates = true
            state.settings.error = nil
        }

        // Complete all operations
        await store.receive(\.history.entitiesResponse) { state in
            state.history.isLoading = false
            state.history.entities = []
        }

        await store.receive(\.automations.automationsResponse) { state in
            state.automations.isLoading = false
        }

        await store.receive(\.actions.actionsResponse) { state in
            state.actions.isLoading = false
        }

        await store.receive(\.settings.windowStatesResponse) { state in
            state.settings.isLoadingWindowStates = false
            state.settings.windowContentState = WindowContentState(windowStates: [])
        }
    }

    @Test("scenePhaseChanged with mock data refreshes successfully")
    @MainActor
    func testScenePhaseChangedWithMockData() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.serverClient = .previewValue
            $0.liveActivity = .testValue
            $0.pushNotification = .testValue
        }

        // Disable exhaustive testing to avoid issues with exact date matching in WindowState
        store.exhaustivity = .off

        await store.send(.scenePhaseChanged(old: .inactive, new: .active))

        // Wait for all actions to complete
        await store.receive(\.automations.refresh)
        await store.receive(\.actions.refresh)
        await store.receive(\.history.refresh)
        await store.receive(\.refreshWindowStates)
        await store.receive(\.startMonitoringLiveActivities)
        await store.receive(\.clearDeliveredNotifications)
        await store.receive(\.settings.refreshWindowStates)
        await store.receive(\.history.entitiesResponse)
        await store.receive(\.automations.automationsResponse)
        await store.receive(\.actions.actionsResponse)
        await store.receive(\.settings.windowStatesResponse)

        // Verify the final state
        let finalState = store.state
        #expect(finalState.automations.automations.count == 3)
        #expect(finalState.actions.actions.count == 1)
        #expect(finalState.settings.windowContentState?.windowStates.count == 1)
        #expect(finalState.settings.windowContentState?.windowStates.first?.name == "Living Room Window")
        #expect(finalState.history.entities.count == 2)  // Preview value has 2 entities
    }

    @Test("scenePhaseChanged ignores non-active transitions")
    @MainActor
    func testScenePhaseChangedIgnoresNonActiveTransitions() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.serverClient = .testValue
            $0.liveActivity = .testValue
            $0.pushNotification = .testValue
        }

        // Send the scene change action for active -> background transition
        // This should not trigger any refresh actions
        await store.send(.scenePhaseChanged(old: .active, new: .background))

        // No refresh actions should be dispatched
    }

    @Test("scenePhaseChanged ignores active to inactive transition")
    @MainActor
    func testScenePhaseChangedIgnoresActiveToInactive() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.serverClient = .testValue
            $0.liveActivity = .testValue
            $0.pushNotification = .testValue
        }

        // Send the scene change action for active -> inactive transition
        // This should not trigger any refresh actions
        await store.send(.scenePhaseChanged(old: .active, new: .inactive))

        // No refresh actions should be dispatched
    }

    @Test("scenePhaseChanged triggers monitoring on app launch")
    @MainActor
    func testScenePhaseChangedTriggersMonitoring() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.serverClient = .testValue
            $0.liveActivity = .testValue
            $0.pushNotification = .testValue
        }

        // Initial app launch triggers monitoring
        await store.send(.scenePhaseChanged(old: .inactive, new: .active))

        await store.receive(\.automations.refresh) { state in
            state.automations.isLoading = true
            state.automations.error = nil
        }

        await store.receive(\.actions.refresh) { state in
            state.actions.isLoading = true
            state.actions.alert = nil
        }

        await store.receive(\.history.refresh) { state in
            state.history.isLoading = true
            state.history.alert = nil
        }

        await store.receive(\.refreshWindowStates)

        await store.receive(\.startMonitoringLiveActivities)

        await store.receive(\.clearDeliveredNotifications)

        await store.receive(\.settings.refreshWindowStates) { state in
            state.settings.isLoadingWindowStates = true
            state.settings.error = nil
        }

        // Wait for all operations to complete
        await store.receive(\.history.entitiesResponse) { state in
            state.history.isLoading = false
            state.history.entities = []
        }

        await store.receive(\.automations.automationsResponse) { state in
            state.automations.isLoading = false
        }

        await store.receive(\.actions.actionsResponse) { state in
            state.actions.isLoading = false
        }

        await store.receive(\.settings.windowStatesResponse) { state in
            state.settings.isLoadingWindowStates = false
            state.settings.windowContentState = WindowContentState(windowStates: [])
        }
    }

    @Test("refreshWindowStates delegates to settings feature")
    @MainActor
    func testRefreshWindowStates() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.serverClient = .testValue
            $0.liveActivity = .testValue
            $0.pushNotification = .testValue
        }

        await store.send(.refreshWindowStates)

        await store.receive(\.settings.refreshWindowStates) { state in
            state.settings.isLoadingWindowStates = true
            state.settings.error = nil
        }

        await store.receive(\.settings.windowStatesResponse) { state in
            state.settings.isLoadingWindowStates = false
            state.settings.windowContentState = WindowContentState(windowStates: [])
        }
    }

    @Test("scenePhaseChanged dispatches clearDeliveredNotifications on app activation")
    @MainActor
    func testClearDeliveredNotificationsOnActivation() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.serverClient = .testValue
            $0.liveActivity = .testValue
            $0.pushNotification = .testValue
        }

        await store.send(.scenePhaseChanged(old: .inactive, new: .active))

        // Verify that all parallel actions are dispatched (including clearDeliveredNotifications)
        // Note: Actions may arrive in any order due to parallel execution via .merge()
        await store.receive(\.automations.refresh) { state in
            state.automations.isLoading = true
            state.automations.error = nil
        }

        await store.receive(\.actions.refresh) { state in
            state.actions.isLoading = true
            state.actions.alert = nil
        }

        await store.receive(\.history.refresh) { state in
            state.history.isLoading = true
            state.history.alert = nil
        }

        await store.receive(\.refreshWindowStates)

        await store.receive(\.startMonitoringLiveActivities)

        await store.receive(\.clearDeliveredNotifications)

        await store.receive(\.settings.refreshWindowStates) { state in
            state.settings.isLoadingWindowStates = true
            state.settings.error = nil
        }

        await store.receive(\.history.entitiesResponse) { state in
            state.history.isLoading = false
            state.history.entities = []
        }

        await store.receive(\.automations.automationsResponse) { state in
            state.automations.isLoading = false
        }

        await store.receive(\.actions.actionsResponse) { state in
            state.actions.isLoading = false
        }

        await store.receive(\.settings.windowStatesResponse) { state in
            state.settings.isLoadingWindowStates = false
            state.settings.windowContentState = WindowContentState(windowStates: [])
        }
    }
}
