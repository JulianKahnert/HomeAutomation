//
//  WindowManagerTests.swift
//  HomeAutomationKitTests
//

import Foundation
@testable import HAApplicationLayer
import HAModels
import Synchronization
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

    @Test("the content state the app fetches keeps the überschritten flag, the counts and the order of the last update")
    func fetchedContentStateMatchesLastUpdate() async throws {
        await open("Fenster", in: "Küche", minutesAfterStart: 0, limit: 30 * 60)
        await open("Tür", in: "Flur", minutesAfterStart: 1, limit: 10 * 60)
        await markOverdue("Fenster", in: "Küche")

        let fetched = await manager.contentState()
        #expect(fetched == (try #require(await sender.contentStates.last)))
        #expect(fetched.windows.map(\.room) == ["Küche", "Flur"])
        #expect(fetched.windows.map(\.isOverdue) == [true, false])
        #expect(fetched.overdueCount == 1)
        #expect(fetched.staleDate == Self.start.addingTimeInterval(11 * 60))
    }

    @Test("the stale date counts windows cut off by the cap, when more than 20 windows are überschritten")
    func staleDateIncludesWindowsBeyondTheCap() async throws {
        for index in 0..<21 {
            await open("Fenster \(index)", in: "Raum \(index)", minutesAfterStart: Double(index), limit: 60)
        }
        await open("Tür", in: "Flur", minutesAfterStart: 0, limit: 40 * 60)
        for index in 0..<21 {
            await markOverdue("Fenster \(index)", in: "Raum \(index)")
        }

        let last = try #require(await sender.updates.last)
        #expect(last.contentState.windows.allSatisfy { $0.isOverdue })
        #expect(last.contentState.openCount == 22)
        #expect(last.options.staleDate == Self.start.addingTimeInterval(40 * 60))
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

@Suite("WindowManager outdoor temperature")
struct WindowManagerOutdoorTemperatureTests {
    private static let start = Date(timeIntervalSince1970: 1_800_000_000)

    private static func contact(_ name: String, in room: String) -> EntityId {
        EntityId(placeId: room, name: name, characteristicsName: nil, characteristic: .contactSensor)
    }

    private static func open(_ name: String, in room: String, on manager: WindowManager) async {
        let entityId = contact(name, in: room)
        let state = WindowOpenState(entityId: entityId, opened: start, maxOpenDuration: 25 * 60)
        await manager.setWindowOpenState(entityId: entityId, to: state)
    }

    @Test("an update carries the latest outdoor temperature reading")
    func updateCarriesLatestOutdoorTemperature() async throws {
        let sender = RecordingNotificationSender()
        let manager = WindowManager(notificationSender: sender, now: { Self.start }, outdoorTemperature: { 7.5 })

        await Self.open("Fenster", in: "Küche", on: manager)

        let state = try #require(await sender.contentStates.last)
        #expect(state.outdoorTemperature == 7.5)
    }

    @Test("an update carries no outdoor temperature when no reading exists")
    func updateCarriesNoOutdoorTemperatureWithoutReading() async throws {
        let sender = RecordingNotificationSender()
        let manager = WindowManager(notificationSender: sender, now: { Self.start }, outdoorTemperature: { nil })

        await Self.open("Fenster", in: "Küche", on: manager)

        let state = try #require(await sender.contentStates.last)
        #expect(state.outdoorTemperature == nil)
    }
}

@Suite("WindowManager periodic refresh")
struct WindowManagerRefreshTests {
    private static let start = Date(timeIntervalSince1970: 1_800_000_000)

    private let sender = RecordingNotificationSender()
    private let sleeper = ManualSleeper()
    private let temperature = OutdoorTemperatureReading(4)
    private let manager: WindowManager

    init() {
        manager = WindowManager(notificationSender: sender,
                                now: { Self.start },
                                outdoorTemperature: { [temperature] in temperature.value },
                                sleep: { [sleeper] duration in try await sleeper.sleep(for: duration) })
    }

    private static func contact(_ name: String, in room: String) -> EntityId {
        EntityId(placeId: room, name: name, characteristicsName: nil, characteristic: .contactSensor)
    }

    private func open(_ name: String, in room: String) async {
        let entityId = Self.contact(name, in: room)
        let state = WindowOpenState(entityId: entityId, opened: Self.start, maxOpenDuration: 25 * 60)
        await manager.setWindowOpenState(entityId: entityId, to: state)
    }

    private func close(_ name: String, in room: String) async {
        await manager.setWindowOpenState(entityId: Self.contact(name, in: room), to: nil)
    }

    @Test("while a window is open, an update with priority 5, no alert and the current outdoor temperature follows every 15 minutes")
    func refreshRunsEveryFifteenMinutesWhileWindowIsOpen() async throws {
        await open("Fenster", in: "Küche")
        #expect(await sleeper.nextSleep() == .seconds(15 * 60))

        temperature.value = 5.5
        sleeper.wake()
        #expect(await sleeper.nextSleep() == .seconds(15 * 60))

        temperature.value = nil
        sleeper.wake()
        #expect(await sleeper.nextSleep() == .seconds(15 * 60))

        let refreshes = await sender.updates.dropFirst()
        #expect(refreshes.map(\.options.priority) == [.low, .low])
        #expect(refreshes.allSatisfy { $0.options.alert == nil })
        #expect(refreshes.map(\.contentState.outdoorTemperature) == [5.5, nil])
        #expect(refreshes.allSatisfy { $0.contentState.windows.map(\.room) == ["Küche"] })
        #expect(refreshes.allSatisfy { $0.options.staleDate == Self.start.addingTimeInterval(25 * 60) })
    }

    @Test("the refresh stops when the last window closes")
    func refreshStopsAfterLastWindowCloses() async throws {
        await open("Fenster", in: "Küche")
        await open("Tür", in: "Flur")
        _ = await sleeper.nextSleep()

        await close("Fenster", in: "Küche")
        #expect(sleeper.pendingCount == 1)

        await close("Tür", in: "Flur")
        #expect(sleeper.pendingCount == 0)
        sleeper.wake()

        let events = await sender.events
        #expect(events.last == .end(activityType: WindowContentState.activityTypeName))
        #expect(await sender.updates.allSatisfy { $0.options.priority == .high })
    }
}

/// The latest stored outdoor temperature reading, changeable while a test runs.
private final class OutdoorTemperatureReading: Sendable {
    private let reading: Mutex<Double?>

    init(_ value: Double?) {
        reading = Mutex(value)
    }

    var value: Double? {
        get { reading.withLock { $0 } }
        set { reading.withLock { $0 = newValue } }
    }
}

@Suite("WindowContentState payload")
struct WindowContentStatePayloadTests {
    @Test("the payload decodes to the same content state, stale date included")
    func payloadRoundTripsStaleDate() throws {
        let opened = Date(timeIntervalSince1970: 1_800_000_000)
        let window = WindowContentState.Window(id: WindowContentState.Window.id(room: "Küche", name: "Fenster"),
                                               name: "Fenster",
                                               room: "Küche",
                                               opened: opened,
                                               closeBy: opened.addingTimeInterval(25 * 60),
                                               isOverdue: false)
        let state = WindowContentState(sortedWindows: [window], outdoorTemperature: 7.5)

        let decoded = try JSONDecoder().decode(WindowContentState.self, from: JSONEncoder().encode(state))

        #expect(decoded == state)
        #expect(decoded.staleDate == opened.addingTimeInterval(25 * 60))
    }
}
