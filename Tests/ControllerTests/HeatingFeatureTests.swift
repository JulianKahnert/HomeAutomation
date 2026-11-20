//
//  HeatingFeatureTests.swift
//  ControllerTests
//

import ComposableArchitecture
@testable import Controller
import Foundation
import HAModels
import Testing

private final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    func append(_ entry: String) { lock.withLock { entries.append(entry) } }
    var all: [String] { lock.withLock { entries } }
}

@MainActor
@Suite("HeatingFeature")
struct HeatingFeatureTests {
    private struct Failure: Error, Equatable {}

    private nonisolated static func heatingAutomation(_ placeId: String) -> AutomationInfo {
        AutomationInfo(name: "heating-\(placeId)", isActive: true, isRunning: false, type: "RoomHeating",
                       entities: [EntityId(placeId: placeId, name: "Thermo", characteristicsName: nil, characteristic: .heating)])
    }

    private nonisolated static func detail(_ placeId: String, _ range: HeatingRange) -> HeatingRoomDetail {
        HeatingRoomDetail(placeId: placeId, name: placeId, range: range, istSource: .thermostats(["Thermo"]), radiators: ["Thermo"],
                          samples: [HeatingSample(date: Date(timeIntervalSince1970: 1_000), ist: 20, sollPlan: 21, valves: [10])])
    }

    private func store(automations: [AutomationInfo], requests: RequestLog = RequestLog()) -> TestStoreOf<HeatingFeature> {
        let store = TestStore(initialState: HeatingFeature.State()) {
            HeatingFeature()
        } withDependencies: {
            $0.serverClient.getAutomations = { automations }
            $0.serverClient.getHeatingRoom = { placeId, range in
                requests.append("\(placeId) \(range.rawValue)")
                return Self.detail(placeId, range)
            }
        }
        return store
    }

    @Test("loading lists the rooms with a heating automation and shows the first one for 24 h")
    func loadSelectsFirstRoom() async {
        let requests = RequestLog()
        let store = store(automations: [AutomationInfo(name: "Other", isActive: true, isRunning: false, type: "Turn"),
                                        Self.heatingAutomation("Bad"), Self.heatingAutomation("Küche")], requests: requests)
        store.exhaustivity = .off
        await store.send(.task)
        await store.receive(\.roomsResponse.success)
        await store.receive(\.detailResponse.success)
        #expect(store.state.rooms.map(\.placeId) == ["Bad", "Küche"])
        #expect(store.state.selectedPlaceId == "Bad")
        #expect(store.state.range == .day)
        #expect(store.state.detail?.placeId == "Bad")
        #expect(requests.all == ["Bad 24h"])
    }

    @Test("changing the range reloads the selected room for that range")
    func rangeChangeReloads() async {
        let requests = RequestLog()
        let store = store(automations: [Self.heatingAutomation("Bad")], requests: requests)
        store.exhaustivity = .off
        await store.send(.task)
        await store.receive(\.roomsResponse.success)
        await store.receive(\.detailResponse.success)
        await store.send(.binding(.set(\.range, .week)))
        await store.receive(\.detailResponse.success)
        #expect(requests.all == ["Bad 24h", "Bad 7d"])
        #expect(store.state.detail?.range == .week)
    }

    @Test("selecting another room loads its detail")
    func selectRoom() async {
        let requests = RequestLog()
        let store = store(automations: [Self.heatingAutomation("Bad"), Self.heatingAutomation("Küche")], requests: requests)
        store.exhaustivity = .off
        await store.send(.task)
        await store.receive(\.roomsResponse.success)
        await store.receive(\.detailResponse.success)
        await store.send(.selectRoom("Küche"))
        await store.receive(\.detailResponse.success)
        #expect(store.state.selectedPlaceId == "Küche")
        #expect(requests.all == ["Bad 24h", "Küche 24h"])
    }

    @Test("closing the detail clears the selection")
    func closeDetail() async {
        let store = store(automations: [Self.heatingAutomation("Bad")])
        store.exhaustivity = .off
        await store.send(.task)
        await store.receive(\.roomsResponse.success)
        await store.receive(\.detailResponse.success)
        await store.send(.selectRoom(nil))
        #expect(store.state.selectedPlaceId == nil)
        #expect(store.state.detail == nil)
    }

    @Test("without heating automations there are no rooms and nothing is requested")
    func noRooms() async {
        let requests = RequestLog()
        let store = store(automations: [AutomationInfo(name: "Other", isActive: true, isRunning: false, type: "Turn")], requests: requests)
        store.exhaustivity = .off
        await store.send(.task)
        await store.receive(\.roomsResponse.success)
        #expect(store.state.rooms.isEmpty)
        #expect(store.state.error == nil)
        #expect(requests.all.isEmpty)
    }

    @Test("an unreachable server is an error state without rooms")
    func serverNotReachable() async {
        let store = TestStore(initialState: HeatingFeature.State()) {
            HeatingFeature()
        } withDependencies: {
            $0.serverClient.getAutomations = { throw Failure() }
        }
        store.exhaustivity = .off
        await store.send(.task)
        await store.receive(\.roomsResponse.failure)
        #expect(store.state.error != nil)
        #expect(store.state.rooms.isEmpty)
    }

    @Test("a failing detail keeps the rooms and sets a detail error")
    func detailFailure() async {
        let store = TestStore(initialState: HeatingFeature.State()) {
            HeatingFeature()
        } withDependencies: {
            $0.serverClient.getAutomations = { [Self.heatingAutomation("Bad")] }
            $0.serverClient.getHeatingRoom = { _, _ in throw Failure() }
        }
        store.exhaustivity = .off
        await store.send(.task)
        await store.receive(\.roomsResponse.success)
        await store.receive(\.detailResponse.failure)
        #expect(store.state.rooms.count == 1)
        #expect(store.state.detailError != nil)
        #expect(store.state.detail == nil)
    }

    @Test("a refresh keeps the selected room and range")
    func refreshKeepsSelection() async {
        let requests = RequestLog()
        let store = store(automations: [Self.heatingAutomation("Bad"), Self.heatingAutomation("Küche")], requests: requests)
        store.exhaustivity = .off
        await store.send(.task)
        await store.receive(\.roomsResponse.success)
        await store.receive(\.detailResponse.success)
        await store.send(.selectRoom("Küche"))
        await store.receive(\.detailResponse.success)
        await store.send(.binding(.set(\.range, .twoHours)))
        await store.receive(\.detailResponse.success)
        await store.send(.refresh)
        await store.receive(\.roomsResponse.success)
        await store.receive(\.detailResponse.success)
        #expect(requests.all.last == "Küche 2h")
    }
}
