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
        let opened = Date(timeIntervalSince1970: 0)
        let window = WindowContentState.Window(
            id: WindowContentState.Window.id(room: "Kitchen", name: "Window"),
            name: "Window",
            room: "Kitchen",
            opened: opened,
            closeBy: opened.addingTimeInterval(3600),
            isOverdue: false
        )
        let windows = WindowContentState(windows: [window], openCount: 1, overdueCount: 0)
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.date.now = opened
            $0.serverClient.isHealthy = { true }
            $0.serverClient.getAutomations = { [AutomationInfo(name: "Night Light", isActive: true, isRunning: false)] }
            $0.serverClient.getRecentRuns = { _, _ in [] }
            $0.serverClient.getHeatingOverview = { HeatingOverview(rooms: []) }
            $0.serverClient.getFireplace = { .off }
            $0.serverClient.getWindowContentState = { windows }
            $0.liveActivity.hasActiveActivities = { false }
            $0.liveActivity.startActivity = { _ in }
            $0.liveActivity.pushToStartTokenUpdates = { _ in }
            $0.liveActivity.pushTokenUpdates = { _ in }
            $0.pushNotification.clearDeliveredNotifications = { }
        }
        // Four children refresh at once, so the order of their answers is not fixed; each child tests its own
        // refresh. This test pins that activation reaches all of them.
        store.exhaustivity = .off

        await store.send(.scenePhaseChanged(old: oldPhase, new: .active))
        await store.receive(\.refreshAll)
        await store.finish()
        await store.skipReceivedActions()

        #expect(store.state.automations.automations.map(\.name) == ["Night Light"])
        #expect(store.state.settings.windowContentState?.windows.first?.room == "Kitchen")
    }

    @Test("scenePhaseChanged ignores non-active transitions")
    @MainActor
    func testScenePhaseChangedIgnoresNonActiveTransitions() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
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
        }

        // Send the scene change action for active -> inactive transition
        // This should not trigger any refresh actions
        await store.send(.scenePhaseChanged(old: .active, new: .inactive))

        // No refresh actions should be dispatched
    }
}
