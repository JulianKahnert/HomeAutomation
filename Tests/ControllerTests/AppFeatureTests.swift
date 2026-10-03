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
import SwiftUI
import Testing

@Suite("AppFeature Tests")
struct AppFeatureTests {

    @Test("activation from inactive or background sends refreshAll", arguments: [ScenePhase.inactive, .background])
    @MainActor
    func activationRefreshesAll(oldPhase: ScenePhase) async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.serverClient = .previewValue
            $0.liveActivity = .testValue
            $0.pushNotification = .testValue
        }
        // Each child owns its refresh; this test only pins that activation reaches them.
        store.exhaustivity = .off

        await store.send(.scenePhaseChanged(old: oldPhase, new: .active))
        await store.receive(\.refreshAll)
        await store.finish()
        await store.skipReceivedActions()

        #expect(store.state.automations.automations.count == 3)
        #expect(store.state.settings.windowContentState?.windowStates.first?.name == "Living Room Window")
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
}
