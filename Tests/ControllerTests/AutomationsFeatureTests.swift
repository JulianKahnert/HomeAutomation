//
//  AutomationsFeatureTests.swift
//  ControllerTests
//

import ComposableArchitecture
@testable import Controller
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
        var state = AutomationsFeature.State()
        state.$automations.withLock { $0 = automations }
        state.$grouping.withLock { $0 = .status }

        #expect(state.sections.map(\.title) == ["Active", "Inactive"])
        #expect(state.sections[0].automations.map(\.name) == ["Hallway", "Evening"])
    }

    @Test("type grouping uses the type label")
    func groupsByType() {
        var state = AutomationsFeature.State()
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
            $0.error = "Failed to change Evening: \(ActivateError().localizedDescription)"
        }
    }
}
