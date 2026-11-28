//
//  OverviewFeatureTests.swift
//  ControllerTests
//

import ComposableArchitecture
@testable import Controller
import Foundation
import HAModels
import Synchronization
import Testing

@MainActor
@Suite("OverviewFeature")
struct OverviewFeatureTests {
    private func run(_ outcome: AutomationRun.Outcome, error: String? = nil) -> AutomationRun {
        AutomationRun(
            automationName: "Night Light",
            startedAt: Date(timeIntervalSince1970: 0),
            trigger: AutomationTrigger(kind: .sunset, entityId: nil, summary: "Sunset"),
            outcome: outcome,
            errorDescription: error
        )
    }

    @Test("refresh fills the status and sorts the shared automations")
    func refreshFillsSnapshot() async {
        let now = Date(timeIntervalSince1970: 100_000)
        let completed = run(.completed)
        let alpha = AutomationInfo(name: "Alpha", isActive: true, isRunning: false)
        let zebra = AutomationInfo(name: "Zebra", isActive: true, isRunning: false)
        let store = TestStore(initialState: OverviewFeature.State()) {
            OverviewFeature()
        } withDependencies: {
            $0.date.now = now
            $0.serverClient.isHealthy = { true }
            $0.serverClient.getAutomations = { [zebra, alpha] }
            $0.serverClient.getRecentRuns = { _, _ in [completed] }
        }

        await store.send(.refresh)
        await store.receive(\.refreshResponse.success) {
            $0.isHealthy = true
            $0.lastUpdated = now
            $0.recentRuns = [completed]
            $0.$automations.withLock { $0 = [alpha, zebra] }
        }
    }

    @Test("stopping an automation refreshes the overview")
    func stopRefreshes() async {
        let now = Date(timeIntervalSince1970: 100_000)
        let stopped = Mutex<[String]>([])
        let store = TestStore(initialState: OverviewFeature.State()) {
            OverviewFeature()
        } withDependencies: {
            $0.date.now = now
            $0.serverClient.stop = { name in stopped.withLock { $0.append(name) } }
            $0.serverClient.isHealthy = { true }
            $0.serverClient.getAutomations = { [] }
            $0.serverClient.getRecentRuns = { _, _ in [] }
        }

        await store.send(.stopButtonTapped("Night Light"))
        await store.receive(\.stopResponse)
        await store.receive(\.refreshResponse.success) {
            $0.isHealthy = true
            $0.lastUpdated = now
        }

        #expect(stopped.withLock { $0 } == ["Night Light"])
    }

    @Test("a failed stop has its own error and leaves the server status alone")
    func stopFailureKeepsHealth() async {
        struct StopError: Error, LocalizedError { var errorDescription: String? { "stop failed" } }
        var state = OverviewFeature.State()
        state.isHealthy = true
        let store = TestStore(initialState: state) {
            OverviewFeature()
        } withDependencies: {
            $0.serverClient.stop = { _ in throw StopError() }
        }

        await store.send(.stopButtonTapped("Night Light"))
        await store.receive(\.stopResponse) {
            $0.stopError = "stop failed"
        }
        #expect(store.state.error == nil)
    }

    @Test("polls every 30 seconds until the task is cancelled")
    func pollingStopsOnCancel() async {
        let now = Date(timeIntervalSince1970: 100_000)
        let clock = TestClock()
        let store = TestStore(initialState: OverviewFeature.State()) {
            OverviewFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date.now = now
            $0.serverClient.isHealthy = { true }
            $0.serverClient.getAutomations = { [] }
            $0.serverClient.getRecentRuns = { _, _ in [] }
        }

        let task = await store.send(.task)
        await store.receive(\.refresh)
        await store.receive(\.refreshResponse.success) {
            $0.isHealthy = true
            $0.lastUpdated = now
        }

        await clock.advance(by: .seconds(30))
        await store.receive(\.refresh)
        await store.receive(\.refreshResponse.success)

        // An exhaustive store fails on any refresh that still arrives after this.
        await task.cancel()
        await clock.advance(by: .seconds(60))
    }

    @Test("tapping a running automation switches to its tab and opens the details")
    func openAutomationFromRunningRow() async {
        var state = AppFeature.State()
        state.automations.$automations.withLock {
            $0 = [AutomationInfo(name: "Night Light", isActive: true, isRunning: true, type: "MotionAtNight")]
        }
        let store = TestStore(initialState: state) {
            AppFeature()
        }
        store.exhaustivity = .off

        await store.send(\.overview.automationTapped, "Night Light")
        await store.receive(\.overview.delegate)
        await store.receive(\.automations.openAutomation)
        #expect(store.state.selectedTab == .automations)
        #expect(store.state.automations.path.first?.details?.automation.name == "Night Light")
    }

    @Test("a run's Open Automation button switches to its tab and opens the details")
    func openAutomationFromRun() async {
        var state = AppFeature.State()
        state.automations.$automations.withLock {
            $0 = [AutomationInfo(name: "Night Light", isActive: true, isRunning: false, type: "MotionAtNight")]
        }
        state.overview.path.append(.run(RunDetailFeature.State(run: run(.completed))))
        let store = TestStore(initialState: state) {
            AppFeature()
        }
        store.exhaustivity = .off

        await store.send(\.overview.path[id: 0].run.openAutomationButtonTapped)
        await store.receive(\.overview.delegate)
        await store.receive(\.automations.openAutomation)
        #expect(store.state.selectedTab == .automations)
        #expect(store.state.automations.path.first?.details?.automation.name == "Night Light")
    }
}
