//
//  AutomationDetailsTests.swift
//  ControllerTests
//

import ComposableArchitecture
@testable import Controller
import Foundation
import HAModels
import Testing

@MainActor
@Suite("AutomationDetails")
struct AutomationDetailsTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let motion = EntityId(placeId: "Hall", name: "Eve Motion", characteristicsName: nil, characteristic: .motionSensor)
    private let thermo = EntityId(placeId: "Hall", name: "Thermo", characteristicsName: nil, characteristic: .temperatureSensor)

    private func info(type: String, recordsRuns: Bool = true, isRunning: Bool = false, entities: [EntityId] = []) -> AutomationInfo {
        AutomationInfo(name: "Night Light", isActive: true, isRunning: isRunning, type: type, recordsRuns: recordsRuns, entities: entities)
    }

    @Test("runs of the last 24 hours are loaded when the automation records them")
    func runsLoadedWhenRecorded() async {
        let recorded = AutomationRun(
            automationName: "Night Light",
            startedAt: now,
            trigger: AutomationTrigger(kind: .sunset, entityId: nil, summary: "Sunset"),
            outcome: .completed
        )
        let store = TestStore(initialState: AutomationDetails.State(automation: Shared(value: info(type: "Turn")))) {
            AutomationDetails()
        } withDependencies: {
            $0.date.now = now
            $0.serverClient.getRuns = { name, start, _, _ in
                name == "Night Light" && start == now.addingTimeInterval(-86_400) ? [recorded] : []
            }
        }

        await store.send(.task) {
            $0.end = now
        }
        await store.receive(\.runsResponse.success) {
            $0.runs = [recorded]
        }
    }

    @Test("an automation without run recording requests no runs")
    func noRunsWhenNotRecorded() async {
        let store = TestStore(initialState: AutomationDetails.State(automation: Shared(value: info(type: "HealthCheck", recordsRuns: false)))) {
            AutomationDetails()
        } withDependencies: {
            $0.date.now = now
            $0.serverClient.getRuns = { _, _, _, _ in
                Issue.record("runs must not be requested")
                return []
            }
        }

        await store.send(.task) {
            $0.end = now
        }
    }

    @Test("the MotionAtNight chart loads the location and only the histories of its devices")
    func motionAtNightChartLoadsOwnDevices() async {
        let motionHistory = EntityHistory(entityId: motion, items: [])
        let location = Location(latitude: 1, longitude: 2)
        let store = TestStore(initialState: AutomationDetails.State(automation: Shared(value: info(type: "MotionAtNight", recordsRuns: false, entities: [motion])))) {
            AutomationDetails()
        } withDependencies: {
            $0.date.now = now
            $0.serverClient.getLocation = { location }
            $0.serverClient.getRoomHistory = { placeId, _, _, _ in
                placeId == "Hall" ? [motionHistory, EntityHistory(entityId: thermo, items: [])] : []
            }
        }
        // `.serverLocation` lives in `UserDefaults.standard`, so a previous run may have stored one.
        store.state.$location.withLock { $0 = nil }

        await store.send(.task) {
            $0.end = now
        }
        await store.receive(\.locationResponse.success) {
            $0.$location.withLock { $0 = location }
        }
        await store.receive(\.historiesResponse.success) {
            $0.histories = [motionHistory]
        }
    }

    @Test("a successful stop marks the automation as not running and reloads")
    func stopMarksNotRunningAndReloads() async {
        let store = TestStore(initialState: AutomationDetails.State(automation: Shared(value: info(type: "Turn", recordsRuns: false, isRunning: true)))) {
            AutomationDetails()
        } withDependencies: {
            $0.date.now = now
        }

        await store.send(.stopAutomation) {
            $0.isLoading = true
        }
        // `\.stopOperationResponse.success` on `Result<Void, Error>` crashes the Swift 6.4 beta compiler.
        await store.receive(\.stopOperationResponse) {
            $0.isLoading = false
            $0.$automation.withLock { $0.isRunning = false }
        }
        await store.receive(\.task) {
            $0.end = now
        }
    }
}
