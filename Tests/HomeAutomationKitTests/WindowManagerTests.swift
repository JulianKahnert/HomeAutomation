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
        #expect(afterFirstClose.contentState.windows.map(\.room) == ["Flur"])
        #expect(afterFirstClose.contentState.openCount == 1)
        #expect(events[3] == .end(activityType: WindowContentState.activityTypeName))
    }

    // MARK: überschritten

    private func markOverdue(_ name: String, in room: String) async {
        await manager.markWindowOverdue(entityId: Self.contact(name, in: room))
    }

    @Test("reaching the Fensterschließzeit sends one priority-10 update with an alert, the window flagged and sorted first")
    func reachingCloseBySendsOneAlertUpdate() async throws {
        await open("Fenster", in: "Küche", minutesAfterStart: 0, limit: 30 * 60)
        await open("Tür", in: "Flur", minutesAfterStart: 1, limit: 10 * 60)
        await open("Kipp", in: "Bad", minutesAfterStart: 2, limit: 20 * 60)
        let updatesBefore = await sender.updates.count

        await markOverdue("Kipp", in: "Bad")

        let updates = await sender.updates
        #expect(updates.count == updatesBefore + 1)
        let update = try #require(updates.last)
        #expect(update.options.priority == .high)
        #expect(update.options.alert == LiveActivityOptions.Alert(title: "Fenster schließen", body: "Bad: Kipp"))
        #expect(update.contentState.windows.map(\.room) == ["Bad", "Flur", "Küche"])
        #expect(update.contentState.windows.map(\.isOverdue) == [true, false, false])
        #expect(update.contentState.overdueCount == 1)
        #expect(update.contentState.openCount == 3)
    }

    @Test("a window alerts only once, and a closed window not at all")
    func windowAlertsOnlyOnce() async {
        await open("Fenster", in: "Küche", minutesAfterStart: 0)
        await open("Tür", in: "Flur", minutesAfterStart: 1)
        await close("Tür", in: "Flur")

        await markOverdue("Fenster", in: "Küche")
        await markOverdue("Fenster", in: "Küche")
        await markOverdue("Tür", in: "Flur")

        let alerts = await sender.updates.compactMap(\.options.alert)
        #expect(alerts == [LiveActivityOptions.Alert(title: "Fenster schließen", body: "Küche: Fenster")])
    }

    @Test("opening and closing a window sends priority-10 updates without an alert")
    func openAndCloseSendHighPriorityWithoutAlert() async {
        await open("Fenster", in: "Küche", minutesAfterStart: 0)
        await open("Tür", in: "Flur", minutesAfterStart: 1)
        await close("Tür", in: "Flur")

        let options = await sender.updates.map(\.options)
        #expect(options.count == 3)
        #expect(options.allSatisfy { $0.priority == .high && $0.alert == nil })
    }

    @Test("the stale date is the earliest Fensterschließzeit among windows not yet überschritten")
    func staleDateIsEarliestPendingCloseBy() async throws {
        await open("Fenster", in: "Küche", minutesAfterStart: 0, limit: 30 * 60)
        await open("Tür", in: "Flur", minutesAfterStart: 1, limit: 10 * 60)

        let afterOpen = try #require(await sender.updates.last)
        #expect(afterOpen.options.staleDate == Self.start.addingTimeInterval(11 * 60))

        await markOverdue("Tür", in: "Flur")

        let afterOverdue = try #require(await sender.updates.last)
        #expect(afterOverdue.options.staleDate == Self.start.addingTimeInterval(30 * 60))
    }

    @Test("there is no stale date once every window is überschritten")
    func noStaleDateWhenEveryWindowIsOverdue() async throws {
        await open("Fenster", in: "Küche", minutesAfterStart: 0)
        await open("Tür", in: "Flur", minutesAfterStart: 1)
        await markOverdue("Fenster", in: "Küche")
        await markOverdue("Tür", in: "Flur")

        let last = try #require(await sender.updates.last)
        #expect(last.contentState.overdueCount == 2)
        #expect(last.options.staleDate == nil)
    }
}
