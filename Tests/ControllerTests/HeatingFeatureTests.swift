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

    private nonisolated static func room(_ placeId: String, ist: Double?, plan: Double? = 21) -> HeatingOverviewRoom {
        HeatingOverviewRoom(placeId: placeId, name: placeId, shortName: placeId, ist: ist, sollPlan: plan, istSource: .thermostats(["Thermo"]))
    }

    private nonisolated static func detail(_ placeId: String, _ range: HeatingRange) -> HeatingRoomDetail {
        HeatingRoomDetail(placeId: placeId, name: placeId, range: range, istSource: .thermostats(["Thermo"]), radiators: ["Thermo"],
                          samples: [HeatingSample(date: Date(timeIntervalSince1970: 1_000), ist: 20, sollPlan: 21, valves: [10])])
    }

    private func store(rooms: [HeatingOverviewRoom], requests: RequestLog = RequestLog()) -> TestStoreOf<HeatingFeature> {
        let store = TestStore(initialState: HeatingFeature.State()) {
            HeatingFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_800_000_000))
            $0.serverClient.getHeatingOverview = { HeatingOverview(rooms: rooms) }
            $0.serverClient.getHeatingRoom = { placeId, range in
                requests.append("\(placeId) \(range.rawValue)")
                return Self.detail(placeId, range)
            }
        }
        store.exhaustivity = .off
        return store
    }

    private func loaded(_ rooms: [HeatingOverviewRoom], requests: RequestLog = RequestLog()) async -> TestStoreOf<HeatingFeature> {
        let store = store(rooms: rooms, requests: requests)
        await store.send(.task)
        await store.receive(\.overviewResponse.success)
        return store
    }

    // MARK: Overview

    @Test("rooms are sorted coldest first and rooms without an actual value come last")
    func sorting() async {
        let store = await loaded([Self.room("Warm", ist: 22), Self.room("Leer", ist: nil), Self.room("Kalt", ist: 18), Self.room("Ok", ist: 21)])
        #expect(store.state.rooms.map(\.placeId) == ["Kalt", "Ok", "Warm", "Leer"])
    }

    @Test("loading selects nothing and asks for no detail")
    func noSelectionAfterLoad() async {
        let requests = RequestLog()
        let store = await loaded([Self.room("Bad", ist: 20)], requests: requests)
        #expect(store.state.selectedPlaceId == nil)
        #expect(store.state.detail == nil)
        #expect(requests.all.isEmpty)
    }

    @Test("the headline names the coldest room when the worst deviation is too cold")
    func headlineColdest() async {
        let store = await loaded([Self.room("Bad OG", ist: 17.3), Self.room("Küche", ist: 22.2)])
        #expect(store.state.headline == "Bad OG am kältesten · 3,7 K unter Plan")
    }

    @Test("the headline names the warmest room when the worst deviation is too warm")
    func headlineWarmest() async {
        let store = await loaded([Self.room("Bad OG", ist: 20.2), Self.room("Küche", ist: 23.0)])
        #expect(store.state.headline == "Küche am wärmsten · 2,0 K über Plan")
    }

    @Test("the headline says all rooms are in plan when every room is inside the comfort band")
    func headlineAllInPlan() async {
        let store = await loaded([Self.room("Bad OG", ist: 20.5), Self.room("Küche", ist: 21.5)])
        #expect(store.state.headline == "Alle Räume im Plan")
    }

    @Test("the headline has a title and a grey subtitle line")
    func headlineParts() async {
        let cold = await loaded([Self.room("Bad OG", ist: 17.3), Self.room("Küche", ist: 22.2)])
        #expect(cold.state.headlineParts?.title == "Bad OG am kältesten")
        #expect(cold.state.headlineParts?.subtitle == "3,7 K unter Plan")
        let warm = await loaded([Self.room("Bad OG", ist: 20.2), Self.room("Küche", ist: 23.0)])
        #expect(warm.state.headlineParts?.title == "Küche am wärmsten")
        #expect(warm.state.headlineParts?.subtitle == "2,0 K über Plan")
        let ok = await loaded([Self.room("Bad OG", ist: 20.5)])
        #expect(ok.state.headlineParts?.title == "Alle Räume im Plan")
        #expect(ok.state.headlineParts?.subtitle == "jeder Raum innerhalb ±0,5 K")
    }

    @Test("the overview remembers when it was loaded")
    func updatedAt() async {
        let moment = Date(timeIntervalSince1970: 1_800_000_000)
        let store = TestStore(initialState: HeatingFeature.State()) {
            HeatingFeature()
        } withDependencies: {
            $0.date = .constant(moment)
            $0.serverClient.getHeatingOverview = { HeatingOverview(rooms: [Self.room("Bad", ist: 20)]) }
        }
        store.exhaustivity = .off
        await store.send(.task)
        await store.receive(\.overviewResponse.success)
        #expect(store.state.updatedAt == moment)
    }

    @Test("rooms without a delta do not count for the headline")
    func headlineIgnoresRoomsWithoutActual() async {
        let store = await loaded([Self.room("Leer", ist: nil), Self.room("Küche", ist: 21)])
        #expect(store.state.headline == "Alle Räume im Plan")
        let none = await loaded([Self.room("Leer", ist: nil)])
        #expect(none.state.headline == nil)
    }

    // MARK: Detail

    @Test("selecting a room loads its detail for the selected range")
    func selectRoom() async {
        let requests = RequestLog()
        let store = await loaded([Self.room("Bad", ist: 20), Self.room("Küche", ist: 21)], requests: requests)
        await store.send(.selectRoom("Küche"))
        await store.receive(\.detailResponse.success)
        #expect(store.state.selectedPlaceId == "Küche")
        #expect(store.state.detail?.placeId == "Küche")
        #expect(requests.all == ["Küche 24h"])
    }

    @Test("changing the range reloads the selected room for that range")
    func rangeChangeReloads() async {
        let requests = RequestLog()
        let store = await loaded([Self.room("Bad", ist: 20)], requests: requests)
        await store.send(.selectRoom("Bad"))
        await store.receive(\.detailResponse.success)
        await store.send(.binding(.set(\.range, .week)))
        await store.receive(\.detailResponse.success)
        #expect(requests.all == ["Bad 24h", "Bad 7d"])
        #expect(store.state.detail?.range == .week)
    }

    @Test("closing the detail clears the selection")
    func closeDetail() async {
        let store = await loaded([Self.room("Bad", ist: 20)])
        await store.send(.selectRoom("Bad"))
        await store.receive(\.detailResponse.success)
        await store.send(.selectRoom(nil))
        #expect(store.state.selectedPlaceId == nil)
        #expect(store.state.detail == nil)
    }

    @Test("a refresh keeps the selected room and range")
    func refreshKeepsSelection() async {
        let requests = RequestLog()
        let store = await loaded([Self.room("Bad", ist: 20), Self.room("Küche", ist: 21)], requests: requests)
        await store.send(.selectRoom("Küche"))
        await store.receive(\.detailResponse.success)
        await store.send(.binding(.set(\.range, .twoHours)))
        await store.receive(\.detailResponse.success)
        await store.send(.refresh)
        await store.receive(\.overviewResponse.success)
        await store.receive(\.detailResponse.success)
        #expect(requests.all.last == "Küche 2h")
        #expect(store.state.selectedPlaceId == "Küche")
    }

    @Test("a refresh without the selected room clears the selection")
    func refreshDropsVanishedRoom() async {
        let rooms = LockedRooms([Self.room("Bad", ist: 20)])
        let store = TestStore(initialState: HeatingFeature.State()) {
            HeatingFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_800_000_000))
            $0.serverClient.getHeatingOverview = { HeatingOverview(rooms: rooms.value) }
            $0.serverClient.getHeatingRoom = { placeId, range in Self.detail(placeId, range) }
        }
        store.exhaustivity = .off
        await store.send(.task)
        await store.receive(\.overviewResponse.success)
        await store.send(.selectRoom("Bad"))
        await store.receive(\.detailResponse.success)
        rooms.value = [Self.room("Küche", ist: 20)]
        await store.send(.refresh)
        await store.receive(\.overviewResponse.success)
        #expect(store.state.selectedPlaceId == nil)
        #expect(store.state.detail == nil)
    }

    // MARK: Empty and error states

    @Test("without heating rooms there is an empty overview and nothing is requested")
    func noRooms() async {
        let requests = RequestLog()
        let store = await loaded([], requests: requests)
        #expect(store.state.rooms.isEmpty)
        #expect(store.state.error == nil)
        #expect(store.state.headline == nil)
        #expect(requests.all.isEmpty)
    }

    @Test("an unreachable server is an error state without rooms")
    func serverNotReachable() async {
        let store = TestStore(initialState: HeatingFeature.State()) {
            HeatingFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_800_000_000))
            $0.serverClient.getHeatingOverview = { throw Failure() }
        }
        store.exhaustivity = .off
        await store.send(.task)
        await store.receive(\.overviewResponse.failure)
        #expect(store.state.error != nil)
        #expect(store.state.rooms.isEmpty)
    }

    @Test("a failing detail keeps the rooms and sets a detail error")
    func detailFailure() async {
        let store = TestStore(initialState: HeatingFeature.State()) {
            HeatingFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_800_000_000))
            $0.serverClient.getHeatingOverview = { HeatingOverview(rooms: [Self.room("Bad", ist: 20)]) }
            $0.serverClient.getHeatingRoom = { _, _ in throw Failure() }
        }
        store.exhaustivity = .off
        await store.send(.task)
        await store.receive(\.overviewResponse.success)
        await store.send(.selectRoom("Bad"))
        await store.receive(\.detailResponse.failure)
        #expect(store.state.rooms.count == 1)
        #expect(store.state.detailError != nil)
        #expect(store.state.detail == nil)
    }
}

private final class LockedRooms: @unchecked Sendable {
    private let lock = NSLock()
    private var rooms: [HeatingOverviewRoom]
    init(_ rooms: [HeatingOverviewRoom]) { self.rooms = rooms }
    var value: [HeatingOverviewRoom] {
        get { lock.withLock { rooms } }
        set { lock.withLock { rooms = newValue } }
    }
}
