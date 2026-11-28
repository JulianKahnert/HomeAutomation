//
//  HeatingFireplaceFeatureTests.swift
//  ControllerTests
//

import ComposableArchitecture
@testable import Controller
import Foundation
import HAModels
import Testing
import UserNotifications

private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [Bool] = []

    func append(_ entry: Bool) { lock.withLock { entries.append(entry) } }
    var all: [Bool] { lock.withLock { entries } }
}

@MainActor
@Suite("Fireplace in the Heizung tab")
struct HeatingFireplaceFeatureTests {
    private struct Failure: Error, Equatable {}

    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func store(initial: FireplaceState = .off, loaded: FireplaceState = .off,
                       switching: @escaping @Sendable (Bool) async throws -> FireplaceState,
                       calls: Calls = Calls()) -> TestStoreOf<HeatingFeature> {
        var state = HeatingFeature.State()
        state.fireplace = initial
        let now = start
        return TestStore(initialState: state) {
            HeatingFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.serverClient.getHeatingOverview = { HeatingOverview(rooms: []) }
            $0.serverClient.getFireplace = { loaded }
            $0.serverClient.setFireplace = { isOn in
                calls.append(isOn)
                return try await switching(isOn)
            }
        }
    }

    @Test("loading the tab reads the fireplace state from the server")
    func loadsState() async {
        let burning = FireplaceState(isOn: true, since: start.addingTimeInterval(-3_600))
        let store = store(loaded: burning, switching: { _ in .off })
        store.exhaustivity = .off

        await store.send(.task)
        await store.receive(\.fireplaceLoaded.success)

        #expect(store.state.fireplace == burning)
    }

    @Test("switching on shows the state at once and keeps the server's answer")
    func switchOn() async {
        let answer = FireplaceState(isOn: true, since: start.addingTimeInterval(2))
        let calls = Calls()
        let store = store(switching: { _ in answer }, calls: calls)

        await store.send(.setFireplace(true)) {
            $0.fireplace = FireplaceState(isOn: true, since: self.start)
        }
        await store.receive(\.fireplaceSwitched.success) {
            $0.fireplace = answer
        }

        #expect(calls.all == [true])
    }

    @Test("switching off asks the server and shows off")
    func switchOff() async {
        let calls = Calls()
        let store = store(initial: FireplaceState(isOn: true, since: start), switching: { _ in .off }, calls: calls)

        await store.send(.setFireplace(false)) { $0.fireplace = .off }
        await store.receive(\.fireplaceSwitched.success)

        #expect(calls.all == [false])
    }

    @Test("asking for the state the tab shows still asks the server, which may know better")
    func staleTab() async {
        let calls = Calls()
        let answer = FireplaceState(isOn: true, since: start.addingTimeInterval(-60))
        let store = store(initial: FireplaceState(isOn: true, since: start), switching: { _ in answer }, calls: calls)

        await store.send(.setFireplace(true))
        await store.receive(\.fireplaceSwitched.success) { $0.fireplace = answer }

        #expect(calls.all == [true])
    }

    @Test("a failed switch shows the error and goes back to what the switch says")
    func failure() async {
        let truth = FireplaceState.off
        let store = store(loaded: truth, switching: { _ in throw Failure() })

        await store.send(.setFireplace(true)) {
            $0.fireplace = FireplaceState(isOn: true, since: start)
        }
        await store.receive(\.fireplaceSwitched.failure) {
            $0.fireplaceError = Failure().localizedDescription
        }
        await store.receive(\.fireplaceLoaded.success) { $0.fireplace = truth }
        await store.send(.dismissFireplaceError) { $0.fireplaceError = nil }
    }

    @Test("the subtitle says when the fireplace ends, and is empty while it is off")
    func hint() {
        let burning = FireplaceState(isOn: true, since: start)
        let end = start.addingTimeInterval(Fireplace.maxDuration)

        #expect(HeatingFormat.fireplaceHint(burning, now: end.addingTimeInterval(-3_600)) == "Kamin an · endet in 1 h")
        #expect(HeatingFormat.fireplaceHint(burning, now: end.addingTimeInterval(-1_800)) == "Kamin an · endet in < 1 h")
        #expect(HeatingFormat.fireplaceHint(burning, now: end.addingTimeInterval(3_600)) == "Kamin an · endet gleich")
        #expect(HeatingFormat.fireplaceHint(.off, now: start) == nil)
    }

    @Test("the push category carries the action that switches the fireplace on, without opening the app")
    func notificationCategory() {
        let category = FireplaceNotification.category

        #expect(category.identifier == Fireplace.notificationCategory)
        #expect(category.actions.map(\.identifier) == [Fireplace.switchOnActionId])
        #expect(category.actions.first?.options.contains(.foreground) == false)
    }

    @Test("only the fireplace action asks for a switch")
    func notificationAction() {
        #expect(FireplaceNotification.requestedState(forAction: Fireplace.switchOnActionId) == true)
        #expect(FireplaceNotification.requestedState(forAction: UNNotificationDefaultActionIdentifier) == nil)
        #expect(FireplaceNotification.requestedState(forAction: UNNotificationDismissActionIdentifier) == nil)
    }
}
