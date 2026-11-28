//
//  WindowProjectionTests.swift
//  HomeAutomationKitTests
//

import Foundation
@testable import HAApplicationLayer
@testable import HAImplementations
import HAModels
import Testing

private extension Date {
    /// The deadline text keeps whole seconds only.
    var roundedToSecond: Date { Date(timeIntervalSince1970: timeIntervalSince1970.rounded()) }
}

@Suite("WindowProjection Live Activity updates")
struct WindowProjectionTests {
    private static let start = Date(timeIntervalSince1970: 1_800_000_000)
    private static let lueftungslimit: TimeInterval = 25 * 60

    private let sender = RecordingNotificationSender()
    private let manager: HomeManager
    private let projection = WindowProjection()

    init() async {
        manager = await HomeManager(getAdapter: { nil },
                                    storageRepo: MockStorageRepository(),
                                    notificationSender: sender,
                                    location: Location(latitude: 52.52, longitude: 13.405))
    }

    private static func deadlineId(_ name: String, in room: String) -> EntityId {
        .serverOwned(name: "\(room)/\(name)", characteristic: .deadline)
    }

    /// Reports a window's deadline like `WindowOpen` and runs the projection for that change.
    @discardableResult
    private func report(_ deadline: Deadline, _ name: String, in room: String) async throws -> EntityStorageItem {
        let id = Self.deadlineId(name, in: room)
        try await manager.report(id, value: .text(deadline.text))
        let item = try #require(await manager.states(of: .deadline).first { $0.entityId == id })
        try await AutomationRunContext.$event.withValue(.change(entity: item)) {
            try await projection.execute(using: manager)
        }
        return item
    }

    private func open(_ name: String, in room: String, minutesAfterStart: Double, limit: TimeInterval = lueftungslimit) async throws {
        try await report(.running(until: Self.start.addingTimeInterval(minutesAfterStart * 60 + limit)), name, in: room)
    }

    private func close(_ name: String, in room: String) async throws {
        try await report(.none, name, in: room)
    }

    private func markOverdue(_ name: String, in room: String) async throws {
        let id = Self.deadlineId(name, in: room)
        let end = try #require(await manager.states(of: .deadline).first { $0.entityId == id }?.deadline?.end)
        try await report(.overdue(since: end), name, in: room)
    }

    @Test("windows are sorted by Fensterschließzeit, window name as tiebreak")
    func windowsAreSortedByCloseByThenName() async throws {
        try await open("Fenster", in: "Küche", minutesAfterStart: 10)
        try await open("Tür", in: "Bad", minutesAfterStart: 0)
        try await open("Dachfenster", in: "Bad", minutesAfterStart: 10)
        // A shorter Lüftungslimit makes a later window due first.
        try await open("Kipp", in: "Büro", minutesAfterStart: 5, limit: 60)

        let state = try #require(await sender.contentStates.last)
        #expect(state.windows.map(\.name) == ["Kipp", "Tür", "Dachfenster", "Fenster"])
        #expect(state.windows.map(\.room) == ["Büro", "Bad", "Bad", "Küche"])
        #expect(state.windows.first?.closeBy == Self.start.addingTimeInterval(5 * 60 + 60))
    }

    @Test("the list is capped at 20 windows while the counts stay complete")
    func listIsCappedWhileCountsStayComplete() async throws {
        for index in 0..<25 {
            try await open("Fenster \(index)", in: "Raum \(index)", minutesAfterStart: Double(index))
        }

        let state = try #require(await sender.contentStates.last)
        #expect(state.windows.count == 20)
        #expect(state.openCount == 25)
        #expect(state.overdueCount == 0)
        #expect(state.windows.last?.name == "Fenster 19")
    }

    @Test("a window keeps its id across updates, and two same-named windows in different rooms differ")
    func windowIdsAreStableAcrossUpdates() async throws {
        try await open("Fenster", in: "Küche", minutesAfterStart: 0)
        try await open("Fenster", in: "Bad", minutesAfterStart: 1)
        try await open("Tür", in: "Flur", minutesAfterStart: 2)
        try await close("Tür", in: "Flur")

        let states = await sender.contentStates
        let kitchenIds = states.compactMap { state in state.windows.first { $0.room == "Küche" }?.id }
        #expect(kitchenIds.count == 4)
        #expect(Set(kitchenIds).count == 1)
        #expect(Set(try #require(states.last).windows.map(\.id)).count == 2)
    }

    @Test("a window opened now shows the moment its deadline started as its opening time")
    func openedIsWhenTheDeadlineStarted() async throws {
        let before = Date()
        try await open("Fenster", in: "Küche", minutesAfterStart: 0)
        try await markOverdue("Fenster", in: "Küche")

        let window = try #require(await sender.contentStates.last?.windows.first)
        #expect(window.isOverdue)
        #expect(window.opened >= before && window.opened <= Date())
    }

    @Test("an overdue window shows its opening time after a restart, when only the database holds the history")
    func openedSurvivesARestart() async throws {
        let base = Date(timeIntervalSinceNow: -86_400).roundedToSecond
        let id = Self.deadlineId("Fenster", in: "Küche")
        let end = base.addingTimeInterval(1_500)
        let opened = base
        let stored = MockStorageRepository(items: [
            EntityStorageItem(entityId: id, timestamp: opened, deadline: .running(until: end)),
            EntityStorageItem(entityId: id, timestamp: end, deadline: .overdue(since: end))
        ])
        let restarted = await HomeManager(
            getAdapter: { nil },
            storageRepo: stored,
            notificationSender: sender,
            location: Location(latitude: 52.52, longitude: 13.405)
        )
        await restarted.loadCurrentStates(timeout: .seconds(5))

        let window = try #require(await restarted.getWindowContentState().windows.first)

        #expect(window.isOverdue)
        #expect(window.opened == opened)
    }

    @Test("a window reopened into a deadline that ran before shows the reopening as its opening time")
    func openedIsTheLatestOpening() async throws {
        let base = Date(timeIntervalSinceNow: -86_400).roundedToSecond
        let id = Self.deadlineId("Fenster", in: "Küche")
        let end = base.addingTimeInterval(1_500)
        let reopened = base.addingTimeInterval(600)
        let stored = MockStorageRepository(items: [
            EntityStorageItem(entityId: id, timestamp: base, deadline: .running(until: end)),
            EntityStorageItem(entityId: id, timestamp: base.addingTimeInterval(300), deadline: Deadline.none),
            EntityStorageItem(entityId: id, timestamp: reopened, deadline: .running(until: end)),
            EntityStorageItem(entityId: id, timestamp: end, deadline: .overdue(since: end))
        ])
        let restarted = await HomeManager(
            getAdapter: { nil },
            storageRepo: stored,
            notificationSender: sender,
            location: Location(latitude: 52.52, longitude: 13.405)
        )
        await restarted.loadCurrentStates(timeout: .seconds(5))

        let window = try #require(await restarted.getWindowContentState().windows.first)

        #expect(window.opened == reopened)
    }

    @Test("closing a window updates the Live Activity, closing the last one ends it")
    func closingUpdatesAndClosingTheLastEnds() async throws {
        try await open("Fenster", in: "Küche", minutesAfterStart: 0)
        try await open("Tür", in: "Flur", minutesAfterStart: 1)
        try await close("Fenster", in: "Küche")
        try await close("Tür", in: "Flur")

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

    @Test("reaching the Fensterschließzeit sends one priority-10 update with an alert, the window flagged and sorted first")
    func reachingCloseBySendsOneAlertUpdate() async throws {
        try await open("Fenster", in: "Küche", minutesAfterStart: 0, limit: 30 * 60)
        try await open("Tür", in: "Flur", minutesAfterStart: 1, limit: 10 * 60)
        try await open("Kipp", in: "Bad", minutesAfterStart: 2, limit: 20 * 60)
        let updatesBefore = await sender.updates.count

        try await markOverdue("Kipp", in: "Bad")

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

    @Test("only the delivery of the change to überschritten alerts, opening and closing do not")
    func onlyTheOverdueChangeAlerts() async throws {
        try await open("Fenster", in: "Küche", minutesAfterStart: 0)
        try await open("Tür", in: "Flur", minutesAfterStart: 1)
        try await close("Tür", in: "Flur")
        try await markOverdue("Fenster", in: "Küche")
        try await open("Kipp", in: "Bad", minutesAfterStart: 2)

        let alerts = await sender.updates.map(\.options.alert)
        #expect(alerts == [nil, nil, nil, LiveActivityOptions.Alert(title: "Fenster schließen", body: "Küche: Fenster"), nil])
    }

    @Test("a window closed before its overdue change is processed does not alert")
    func closedWindowDoesNotAlert() async throws {
        try await open("Fenster", in: "Küche", minutesAfterStart: 0)
        try await open("Tür", in: "Flur", minutesAfterStart: 1)
        let id = Self.deadlineId("Tür", in: "Flur")
        let end = try #require(await manager.states(of: .deadline).first { $0.entityId == id }?.deadline?.end)
        try await manager.report(id, value: .text(Deadline.overdue(since: end).text))
        let overdue = try #require(await manager.states(of: .deadline).first { $0.entityId == id })
        try await manager.report(id, value: .text(Deadline.none.text))

        try await AutomationRunContext.$event.withValue(.change(entity: overdue)) {
            try await projection.execute(using: manager)
        }

        #expect(await sender.updates.compactMap(\.options.alert).isEmpty)
    }

    @Test("a reminder for a window still überschritten sends the alert again with the current content state")
    func reminderRepeatsTheAlert() async throws {
        try await open("Fenster", in: "Küche", minutesAfterStart: 0)
        try await open("Tür", in: "Flur", minutesAfterStart: 1)
        try await markOverdue("Fenster", in: "Küche")
        let updatesBefore = await sender.updates.count

        #expect(try await WindowProjection.remind(of: Self.deadlineId("Fenster", in: "Küche"), using: manager))

        let updates = await sender.updates
        #expect(updates.count == updatesBefore + 1)
        let update = try #require(updates.last)
        #expect(update.options.priority == .high)
        #expect(update.options.alert == LiveActivityOptions.Alert(title: "Fenster schließen", body: "Küche: Fenster"))
        #expect(update.contentState == updates[updates.count - 2].contentState)
    }

    @Test("a reminder for a window that is not überschritten (still running or closed) sends nothing")
    func reminderForAWindowNotOverdueSendsNothing() async throws {
        try await open("Fenster", in: "Küche", minutesAfterStart: 0)
        try await open("Tür", in: "Flur", minutesAfterStart: 1)
        try await markOverdue("Tür", in: "Flur")
        try await close("Tür", in: "Flur")
        let eventsBefore = await sender.events.count

        #expect(try await WindowProjection.remind(of: Self.deadlineId("Fenster", in: "Küche"), using: manager) == false)
        #expect(try await WindowProjection.remind(of: Self.deadlineId("Tür", in: "Flur"), using: manager) == false)

        #expect(await sender.events.count == eventsBefore)
    }

    @Test("opening and closing a window send priority-10 updates without an alert")
    func openAndCloseSendHighPriorityWithoutAlert() async throws {
        try await open("Fenster", in: "Küche", minutesAfterStart: 0)
        try await open("Tür", in: "Flur", minutesAfterStart: 1)
        try await close("Tür", in: "Flur")

        let options = await sender.updates.map(\.options)
        #expect(options.count == 3)
        #expect(options.allSatisfy { $0.priority == .high && $0.alert == nil })
    }

    @Test("the stale date is the earliest Fensterschließzeit among windows not yet überschritten")
    func staleDateIsEarliestPendingCloseBy() async throws {
        try await open("Fenster", in: "Küche", minutesAfterStart: 0, limit: 30 * 60)
        try await open("Tür", in: "Flur", minutesAfterStart: 1, limit: 10 * 60)
        #expect(try #require(await sender.updates.last).options.staleDate == Self.start.addingTimeInterval(11 * 60))

        try await markOverdue("Tür", in: "Flur")
        #expect(try #require(await sender.updates.last).options.staleDate == Self.start.addingTimeInterval(30 * 60))
    }

    @Test("the content state the app fetches is the one of the last update")
    func fetchedContentStateMatchesLastUpdate() async throws {
        try await open("Fenster", in: "Küche", minutesAfterStart: 0, limit: 30 * 60)
        try await open("Tür", in: "Flur", minutesAfterStart: 1, limit: 10 * 60)
        try await markOverdue("Fenster", in: "Küche")

        let fetched = await manager.getWindowContentState()
        #expect(fetched == (try #require(await sender.contentStates.last)))
        #expect(fetched.windows.map(\.room) == ["Küche", "Flur"])
        #expect(fetched.windows.map(\.isOverdue) == [true, false])
        #expect(fetched.overdueCount == 1)
        #expect(fetched.staleDate == Self.start.addingTimeInterval(11 * 60))
    }

    @Test("the stale date counts windows cut off by the cap, when more than 20 windows are überschritten")
    func staleDateIncludesWindowsBeyondTheCap() async throws {
        for index in 0..<21 {
            try await open("Fenster \(index)", in: "Raum \(index)", minutesAfterStart: Double(index), limit: 60)
        }
        try await open("Tür", in: "Flur", minutesAfterStart: 0, limit: 40 * 60)
        for index in 0..<21 {
            try await markOverdue("Fenster \(index)", in: "Raum \(index)")
        }

        let last = try #require(await sender.updates.last)
        #expect(last.contentState.windows.allSatisfy { $0.isOverdue })
        #expect(last.contentState.openCount == 22)
        #expect(last.options.staleDate == Self.start.addingTimeInterval(40 * 60))
    }

    @Test("there is no stale date once every window is überschritten")
    func noStaleDateWhenEveryWindowIsOverdue() async throws {
        try await open("Fenster", in: "Küche", minutesAfterStart: 0)
        try await open("Tür", in: "Flur", minutesAfterStart: 1)
        try await markOverdue("Fenster", in: "Küche")
        try await markOverdue("Tür", in: "Flur")

        let last = try #require(await sender.updates.last)
        #expect(last.contentState.overdueCount == 2)
        #expect(last.options.staleDate == nil)
    }

    // MARK: outdoor temperature

    @Test("an update carries the outdoor temperature entity's reading, none without a reading")
    func updateCarriesOutdoorTemperature() async throws {
        try await open("Fenster", in: "Küche", minutesAfterStart: 0)
        #expect(try #require(await sender.contentStates.last).outdoorTemperature == nil)

        try await manager.report(.outdoorTemperature, value: .number(7.5))
        try await open("Tür", in: "Flur", minutesAfterStart: 1)
        #expect(try #require(await sender.contentStates.last).outdoorTemperature == 7.5)
    }

    // MARK: quiet refresh

    private static func clockTick(minute: Int) -> HomeEvent {
        let date = Calendar.current.date(from: DateComponents(year: 2027, month: 1, day: 15, hour: 10, minute: minute)) ?? start
        return .time(date: date)
    }

    @Test("with a deadline the clock triggers every 15 minutes, with none it does not")
    func clockTriggersWhileADeadlineExists() async throws {
        #expect(try await projection.shouldTrigger(with: Self.clockTick(minute: 15), using: manager) == false)

        try await open("Fenster", in: "Küche", minutesAfterStart: 0)
        for minute in [0, 15, 30, 45] {
            #expect(try await projection.shouldTrigger(with: Self.clockTick(minute: minute), using: manager))
        }
        #expect(try await projection.shouldTrigger(with: Self.clockTick(minute: 7), using: manager) == false)

        try await close("Fenster", in: "Küche")
        #expect(try await projection.shouldTrigger(with: Self.clockTick(minute: 15), using: manager) == false)
    }

    @Test("the quiet refresh sends priority 5 without an alert and with the current outdoor temperature")
    func quietRefreshIsLowPriority() async throws {
        try await open("Fenster", in: "Küche", minutesAfterStart: 0)
        try await manager.report(.outdoorTemperature, value: .number(5.5))

        try await AutomationRunContext.$event.withValue(Self.clockTick(minute: 15)) {
            try await projection.execute(using: manager)
        }

        let refresh = try #require(await sender.updates.last)
        #expect(refresh.options.priority == .low)
        #expect(refresh.options.alert == nil)
        #expect(refresh.contentState.outdoorTemperature == 5.5)
        #expect(refresh.contentState.windows.map(\.room) == ["Küche"])
        #expect(refresh.options.staleDate == Self.start.addingTimeInterval(25 * 60))
    }

    @Test("the refresh with no window left ends the activity")
    func refreshWithoutWindowEndsTheActivity() async throws {
        try await AutomationRunContext.$event.withValue(Self.clockTick(minute: 15)) {
            try await projection.execute(using: manager)
        }

        #expect(await sender.events == [.end(activityType: WindowContentState.activityTypeName)])
    }

    @Test("only deadline changes trigger, and the lane collapses nothing and never cuts a run")
    func triggersAndLane() async throws {
        let deadline = try await report(.running(until: Self.start), "Fenster", in: "Küche")
        let other = EntityStorageItem(entityId: .outdoorTemperature, temperatureInC: .init(value: 1, unit: .celsius))

        #expect(try await projection.shouldTrigger(with: .change(entity: deadline), using: manager))
        #expect(try await projection.shouldTrigger(with: .change(entity: other), using: manager) == false)
        #expect(try await projection.shouldTrigger(with: .serverStarted, using: manager) == false)
        #expect(projection.lanePolicy == .runEach)
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
