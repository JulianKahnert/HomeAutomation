//
//  HeatingPinTests.swift
//  ControllerTests
//

import ComposableArchitecture
@testable import Controller
import Foundation
import HAModels
import Testing

@MainActor
@Suite("Heating pins")
struct HeatingPinTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var domain: ClosedRange<Date> { start...start.addingTimeInterval(24 * 3_600) }

    private func event(_ source: HeatingEventSource, hours: Double, end: Double? = nil) -> HeatingEvent {
        let date = start.addingTimeInterval(hours * 3_600)
        return HeatingEvent(source: source, title: "t", reason: "r", start: date, end: end.map { start.addingTimeInterval($0 * 3_600) }, pin: date)
    }

    private func layout(_ events: [HeatingEvent], width: Double = 240) -> [HeatingPinLayout.Slot] {
        HeatingPinLayout.slots(events, in: domain, plotWidth: width, pinWidth: 20, rows: 2)
    }

    // MARK: Layout

    @Test("pins with room stay in the first row, one per slot")
    func apart() {
        let slots = layout([event(.plan, hours: 1), event(.window, hours: 12), event(.observed, hours: 23)])
        #expect(slots.map(\.row) == [0, 0, 0])
        #expect(slots.map(\.events.count) == [1, 1, 1])
    }

    @Test("a pin too close to the one before takes the second row")
    func secondRow() {
        let slots = layout([event(.plan, hours: 6), event(.window, hours: 6.5)])
        #expect(slots.map(\.row) == [0, 1])
    }

    @Test("a pin that finds both rows taken joins the last pin of the second row as a +n pin")
    func overflow() {
        let slots = layout([event(.plan, hours: 6), event(.window, hours: 6.5), event(.observed, hours: 6.7), event(.system, hours: 6.8)])
        #expect(slots.count == 2)
        #expect(slots[1].events.count == 3)
        #expect(slots[1].badge == "+3")
        #expect(slots[0].badge == nil)
        #expect(slots.flatMap(\.events).count == 4)
    }

    @Test("a free row is used again after a gap")
    func rowFreesUp() {
        let slots = layout([event(.plan, hours: 6), event(.window, hours: 6.5), event(.observed, hours: 9)])
        #expect(slots.map(\.row) == [0, 1, 0])
    }

    @Test("no events, no slots")
    func empty() {
        #expect(layout([]).isEmpty)
    }

    // MARK: Pin selection by range

    @Test("plan pins show up to 24 h only, everything else in every range")
    func pinSelection() {
        let events = [event(.plan, hours: 1), event(.window, hours: 2, end: 3), event(.observed, hours: 4)]
        #expect(HeatingPinLayout.pins(events, range: .day).count == 3)
        #expect(HeatingPinLayout.pins(events, range: .week).map(\.source) == [.window, .observed])
    }

    @Test("areas are the events with a duration")
    func areas() {
        let events = [event(.plan, hours: 1), event(.window, hours: 2, end: 3), event(.fireplace, hours: 4)]
        #expect(HeatingPinLayout.areas(events).map(\.source) == [.window, .fireplace])
    }

    // MARK: Store

    private func store() -> TestStoreOf<HeatingFeature> {
        var state = HeatingFeature.State()
        state.selectedPlaceId = "Bad"
        let store = TestStore(initialState: state) { HeatingFeature() } withDependencies: {
            $0.serverClient.getHeatingRoom = { placeId, range in
                HeatingRoomDetail(placeId: placeId, name: placeId, range: range, istSource: .thermostats([]), radiators: [], samples: [])
            }
        }
        store.exhaustivity = .off
        return store
    }

    @Test("selecting a pin selects it, the same pin again clears it")
    func toggle() async {
        let store = store()
        await store.send(.selectPin("plan-1")) { $0.selectedPinId = "plan-1" }
        await store.send(.selectPin("plan-1")) { $0.selectedPinId = nil }
    }

    @Test("selecting another pin replaces the selection")
    func replace() async {
        let store = store()
        await store.send(.selectPin("plan-1")) { $0.selectedPinId = "plan-1" }
        await store.send(.selectPin("window-2")) { $0.selectedPinId = "window-2" }
    }

    @Test("changing the range or the room clears the selected pin")
    func clears() async {
        let store = store()
        await store.send(.selectPin("plan-1")) { $0.selectedPinId = "plan-1" }
        await store.send(.set(\.range, .week)) { $0.range = .week; $0.selectedPinId = nil }
        await store.send(.selectPin("plan-1")) { $0.selectedPinId = "plan-1" }
        await store.send(.selectRoom("Küche")) { $0.selectedPlaceId = "Küche"; $0.selectedPinId = nil }
    }
}
