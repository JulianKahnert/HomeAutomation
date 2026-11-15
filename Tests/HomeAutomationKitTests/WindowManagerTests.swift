//
//  WindowManagerTests.swift
//  HomeAutomationKitTests
//

import Foundation
@testable import HAApplicationLayer
import HAModels
import Testing

@Suite("WindowManager Live Activity updates")
struct WindowManagerTests {
    private static let start = Date(timeIntervalSince1970: 1_800_000_000)
    private static let lueftungslimit: TimeInterval = 25 * 60

    private let sender = RecordingNotificationSender()
    private let manager: WindowManager

    init() {
        manager = WindowManager(notificationSender: sender, now: { Self.start })
    }

    private static func contact(_ name: String, in room: String) -> EntityId {
        EntityId(placeId: room, name: name, characteristicsName: nil, characteristic: .contactSensor)
    }

    private func open(_ name: String, in room: String, minutesAfterStart: Double, limit: TimeInterval = lueftungslimit) async {
        let entityId = Self.contact(name, in: room)
        let state = WindowOpenState(entityId: entityId,
                                    opened: Self.start.addingTimeInterval(minutesAfterStart * 60),
                                    maxOpenDuration: limit)
        await manager.setWindowOpenState(entityId: entityId, to: state)
    }

    private func close(_ name: String, in room: String) async {
        await manager.setWindowOpenState(entityId: Self.contact(name, in: room), to: nil)
    }

    @Test("windows are sorted by Fensterschließzeit, window name as tiebreak")
    func windowsAreSortedByCloseByThenName() async throws {
        await open("Fenster", in: "Küche", minutesAfterStart: 10)
        await open("Tür", in: "Bad", minutesAfterStart: 0)
        await open("Dachfenster", in: "Bad", minutesAfterStart: 10)
        // A shorter Lüftungslimit makes a later window due first.
        await open("Kipp", in: "Büro", minutesAfterStart: 5, limit: 60)

        let state = try #require(await sender.contentStates.last)
        #expect(state.windows.map(\.name) == ["Kipp", "Tür", "Dachfenster", "Fenster"])
        #expect(state.windows.map(\.room) == ["Büro", "Bad", "Bad", "Küche"])
        #expect(state.windows.first?.closeBy == Self.start.addingTimeInterval(5 * 60 + 60))
    }

    @Test("the list is capped at 20 windows while the counts stay complete")
    func listIsCappedWhileCountsStayComplete() async throws {
        for index in 0..<25 {
            await open("Fenster \(index)", in: "Raum \(index)", minutesAfterStart: Double(index))
        }

        let state = try #require(await sender.contentStates.last)
        #expect(state.windows.count == 20)
        #expect(state.openCount == 25)
        #expect(state.overdueCount == 0)
        // The windows due last are the ones cut off.
        #expect(state.windows.last?.name == "Fenster 19")
    }

    @Test("a window keeps its id across updates, and two same-named windows in different rooms differ")
    func windowIdsAreStableAcrossUpdates() async throws {
        await open("Fenster", in: "Küche", minutesAfterStart: 0)
        await open("Fenster", in: "Bad", minutesAfterStart: 1)
        await open("Tür", in: "Flur", minutesAfterStart: 2)
        await close("Tür", in: "Flur")

        let states = await sender.contentStates
        let kitchenIds = states.compactMap { state in state.windows.first { $0.room == "Küche" }?.id }
        #expect(kitchenIds.count == 4)
        #expect(Set(kitchenIds).count == 1)

        let last = try #require(states.last)
        #expect(Set(last.windows.map(\.id)).count == 2)
    }

    @Test("closing a window updates the Live Activity, closing the last one ends it")
    func closingUpdatesAndClosingTheLastEnds() async {
        await open("Fenster", in: "Küche", minutesAfterStart: 0)
        await open("Tür", in: "Flur", minutesAfterStart: 1)
        await close("Fenster", in: "Küche")
        await close("Tür", in: "Flur")

        let events = await sender.events
        #expect(events.count == 4)
        guard case let .liveActivity(afterFirstClose) = events[2] else {
            Issue.record("Expected an update after the first close, got \(events[2])")
            return
        }
        #expect(afterFirstClose.windows.map(\.room) == ["Flur"])
        #expect(afterFirstClose.openCount == 1)
        #expect(events[3] == .end(activityType: WindowContentState.activityTypeName))
    }
}
