//
//  SettingsFeatureTests.swift
//  ControllerTests
//

import ComposableArchitecture
@testable import Controller
import Foundation
import HAModels
import Testing

@MainActor
@Suite("SettingsFeature")
struct SettingsFeatureTests {
    private struct Failure: Error, LocalizedError {
        var errorDescription: String? { "server away" }
    }

    @Test("a failed window load resets the running Live Activity")
    func failureResetsRunningActivity() async {
        let updates = LockIsolated<[WindowContentState]>([])
        let store = TestStore(initialState: SettingsFeature.State(isLoadingWindowStates: true)) {
            SettingsFeature()
        } withDependencies: {
            $0.liveActivity.hasActiveActivities = { true }
            $0.liveActivity.updateActivity = { state in updates.withValue { $0.append(state) } }
        }
        store.state.$liveActivitiesEnabled.withLock { $0 = true }

        await store.send(.windowStatesResponse(.failure(Failure()))) {
            $0.isLoadingWindowStates = false
            $0.error = "Failed to load window states: server away"
        }
        await store.finish()

        #expect(updates.value == [.empty])
    }

    @Test("a failed window load leaves Live Activities alone when none runs")
    func failureWithoutActivity() async {
        let store = TestStore(initialState: SettingsFeature.State(isLoadingWindowStates: true)) {
            SettingsFeature()
        } withDependencies: {
            $0.liveActivity.hasActiveActivities = { false }
        }
        store.state.$liveActivitiesEnabled.withLock { $0 = true }

        await store.send(.windowStatesResponse(.failure(Failure()))) {
            $0.isLoadingWindowStates = false
            $0.error = "Failed to load window states: server away"
        }
        await store.finish()
    }

    @Test("a failed window load leaves Live Activities alone when they are off")
    func failureWithActivitiesOff() async {
        let store = TestStore(initialState: SettingsFeature.State(isLoadingWindowStates: true)) {
            SettingsFeature()
        }
        store.state.$liveActivitiesEnabled.withLock { $0 = false }

        await store.send(.windowStatesResponse(.failure(Failure()))) {
            $0.isLoadingWindowStates = false
            $0.error = "Failed to load window states: server away"
        }
        await store.finish()
    }

    @Test("a denied push authorization is handled, not reported")
    func deniedAuthorization() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        } withDependencies: {
            $0.pushNotification.requestAuthorization = { throw Failure() }
        }

        await store.send(.requestPushAuthorization)
        await store.finish()
    }
}
