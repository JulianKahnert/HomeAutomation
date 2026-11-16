//
//  WindowActivityPresentationTests.swift
//  ControllerTests
//

@testable import Controller
import Foundation
import HAModels
import Testing

@Suite("Window Live Activity presentation")
struct WindowActivityPresentationTests {
    private static let start = Date(timeIntervalSince1970: 1_800_000_000)

    private static func window(_ room: String, overdue: Bool = false) -> WindowContentState.Window {
        WindowContentState.Window(id: WindowContentState.Window.id(room: room, name: "Fenster"),
                                  name: "Fenster",
                                  room: room,
                                  opened: start,
                                  closeBy: start.addingTimeInterval(25 * 60),
                                  isOverdue: overdue)
    }

    private static func state(_ windows: [WindowContentState.Window],
                              openCount: Int? = nil,
                              overdueCount: Int? = nil) -> WindowContentState {
        WindowContentState(windows: windows,
                           openCount: openCount ?? windows.count,
                           overdueCount: overdueCount ?? windows.filter(\.isOverdue).count)
    }

    private static let eightRooms = ["Küche", "Bad", "Büro", "Flur", "Schlafzimmer", "Wohnzimmer", "Kinderzimmer", "Keller"]

    @Test("8 windows with a budget of 3 show 3 rows and name the other 5 rooms")
    func eightWindowsShowThreeRowsAndFiveMore() {
        let presentation = WindowActivityPresentation(contentState: Self.state(Self.eightRooms.map { Self.window($0) }),
                                                      rowBudget: 3)

        #expect(presentation.rows.map(\.room) == ["Küche", "Bad", "Büro"])
        #expect(presentation.more?.text == "+5 weitere: Flur, Schlafzimmer, Wohnzimmer, Kinderzimmer, Keller")
        #expect(presentation.more?.isOverdue == false)
    }

    @Test("the header counts offene and überschrittene Fenster")
    func headerCountsOpenAndOverdue() {
        let presentation = WindowActivityPresentation(contentState: Self.state([Self.window("Bad", overdue: true), Self.window("Küche")],
                                                                               openCount: 8,
                                                                               overdueCount: 2),
                                                      rowBudget: 3)

        #expect(presentation.header == "8 offen · 2 überschritten")
    }

    @Test("all windows fit: no +X weitere line")
    func allWindowsFit() {
        let presentation = WindowActivityPresentation(contentState: Self.state([Self.window("Küche"), Self.window("Bad")]),
                                                      rowBudget: 3)

        #expect(presentation.rows.map(\.room) == ["Küche", "Bad"])
        #expect(presentation.more == nil)
    }

    @Test("a room with several hidden windows is named once")
    func hiddenRoomsAreNamedOnce() {
        let windows = ["Küche", "Bad", "Bad", "Bad", "Flur"].map { Self.window($0) }
        let presentation = WindowActivityPresentation(contentState: Self.state(windows), rowBudget: 2)

        #expect(presentation.more?.text == "+3 weitere: Bad, Flur")
    }

    @Test("windows cut off by the server's cap count in +X weitere and end the room list with …")
    func cappedWindowsCountInMore() {
        let windows = ["Küche", "Bad", "Büro", "Flur"].map { Self.window($0) }
        let presentation = WindowActivityPresentation(contentState: Self.state(windows, openCount: 23), rowBudget: 3)

        #expect(presentation.more?.text == "+20 weitere: Flur, …")
    }

    @Test("+X weitere turns red only when a hidden window is überschritten")
    func moreIsRedOnlyForHiddenOverdueWindows() {
        let shownOverdue = Self.state([Self.window("Küche", overdue: true), Self.window("Bad"), Self.window("Flur")])
        #expect(WindowActivityPresentation(contentState: shownOverdue, rowBudget: 1).more?.isOverdue == false)

        let hiddenOverdue = Self.state([Self.window("Küche"), Self.window("Bad"), Self.window("Flur", overdue: true)])
        #expect(WindowActivityPresentation(contentState: hiddenOverdue, rowBudget: 1).more?.isOverdue == true)

        // Überschritten windows beyond the server's cap only show up in the count.
        let cappedOverdue = Self.state([Self.window("Küche"), Self.window("Bad")], openCount: 25, overdueCount: 1)
        #expect(WindowActivityPresentation(contentState: cappedOverdue, rowBudget: 1).more?.isOverdue == true)
    }

    @Test("a stale activity marks the first window not yet überschritten as possibly überschritten")
    func staleActivityMarksFirstPendingWindow() {
        let state = Self.state([Self.window("Küche", overdue: true), Self.window("Bad"), Self.window("Flur")])

        #expect(WindowActivityPresentation(contentState: state, rowBudget: 3, isStale: true).possiblyOverdueWindowId == WindowContentState.Window.id(room: "Bad", name: "Fenster"))
        #expect(WindowActivityPresentation(contentState: state, rowBudget: 3, isStale: false).possiblyOverdueWindowId == nil)

        let allOverdue = Self.state([Self.window("Küche", overdue: true), Self.window("Bad", overdue: true)])
        #expect(WindowActivityPresentation(contentState: allOverdue, rowBudget: 3, isStale: true).possiblyOverdueWindowId == nil)
    }

    @Test("the compact and minimal tint is red once any window is überschritten")
    func compactTintFollowsOverdueCount() {
        #expect(WindowActivityPresentation(contentState: Self.state([Self.window("Küche")]), rowBudget: 1).isAnyOverdue == false)

        let overdueBeyondCap = Self.state([Self.window("Küche")], openCount: 25, overdueCount: 1)
        #expect(WindowActivityPresentation(contentState: overdueBeyondCap, rowBudget: 1).isAnyOverdue == true)
    }

    // MARK: Dynamic Island

    @Test("the expanded Dynamic Island with 8 windows shows two rows and names the other 6 rooms")
    func expandedIslandShowsTwoRows() {
        let presentation = WindowActivityPresentation(contentState: Self.state(Self.eightRooms.map { Self.window($0) }),
                                                      rowBudget: WindowActivityPresentation.expandedRowBudget)

        #expect(presentation.rows.map(\.room) == ["Küche", "Bad"])
        #expect(presentation.more?.text == "+6 weitere: Büro, Flur, Schlafzimmer, Wohnzimmer, Kinderzimmer, Keller")
    }

    @Test("the expanded leading region says how many windows are offen, beyond the server's cap too")
    func expandedLeadingCountsOpenWindows() {
        let presentation = WindowActivityPresentation(contentState: Self.state([Self.window("Küche")], openCount: 23),
                                                      rowBudget: WindowActivityPresentation.expandedRowBudget)

        #expect(presentation.openSummary == "23 offen")
    }

    @Test("the expanded trailing region counts überschrittene Fenster and stays empty without one")
    func expandedTrailingCountsOverdueWindows() {
        let none = Self.state([Self.window("Küche")])
        #expect(WindowActivityPresentation(contentState: none, rowBudget: 2).overdueBadge == nil)

        let twoOverdue = Self.state([Self.window("Bad", overdue: true), Self.window("Küche")], openCount: 25, overdueCount: 2)
        #expect(WindowActivityPresentation(contentState: twoOverdue, rowBudget: 2).overdueBadge == 2)
    }

    @Test("the compact trailing region shows the first window in server order")
    func compactTrailingShowsFirstWindow() {
        let windows = [Self.window("Bad", overdue: true), Self.window("Küche")]
        #expect(WindowActivityPresentation(contentState: Self.state(windows), rowBudget: 2).mostUrgent == windows[0])

        #expect(WindowActivityPresentation(contentState: .empty, rowBudget: 2).mostUrgent == nil)
    }

    @Test("compact and minimal stay uncoloured for a window past its Fensterschließzeit the server has not marked überschritten")
    func compactTintIgnoresTheClock() {
        let past = Date(timeIntervalSince1970: 0)
        let window = WindowContentState.Window(id: WindowContentState.Window.id(room: "Küche", name: "Fenster"),
                                               name: "Fenster",
                                               room: "Küche",
                                               opened: past,
                                               closeBy: past.addingTimeInterval(25 * 60),
                                               isOverdue: false)

        #expect(WindowActivityPresentation(contentState: Self.state([window]), rowBudget: 2).isAnyOverdue == false)
        #expect(WindowActivityPresentation(contentState: Self.state([Self.window("Küche", overdue: true)]), rowBudget: 2).isAnyOverdue == true)
    }

    @Test("the Watch shows the most urgent window and +X weitere offen for the rest")
    func watchShowsFirstWindowAndCountsTheRest() {
        let presentation = WindowActivityPresentation(contentState: Self.state(Self.eightRooms.map { Self.window($0) }),
                                                      rowBudget: WindowActivityPresentation.watchRowBudget)

        #expect(presentation.rows.map(\.room) == ["Küche"])
        #expect(presentation.watchCaption?.text == "+7 weitere offen")
        #expect(presentation.watchCaption?.isOverdue == false)
    }

    @Test("the Watch's +X weitere offen counts windows beyond the server's cap and turns red for a hidden überschritten window")
    func watchCaptionUsesFullCounts() {
        let capped = Self.state([Self.window("Küche"), Self.window("Bad", overdue: true)], openCount: 23, overdueCount: 1)
        let presentation = WindowActivityPresentation(contentState: capped, rowBudget: WindowActivityPresentation.watchRowBudget)

        #expect(presentation.watchCaption?.text == "+22 weitere offen")
        #expect(presentation.watchCaption?.isOverdue == true)
    }

    @Test("a single window on the Watch shows its name below the bar")
    func watchSingleWindowShowsItsName() {
        let presentation = WindowActivityPresentation(contentState: Self.state([Self.window("Küche")]),
                                                      rowBudget: WindowActivityPresentation.watchRowBudget)

        #expect(presentation.watchCaption == WindowActivityPresentation.Caption(text: "Fenster", isOverdue: false))
        #expect(WindowActivityPresentation(contentState: .empty, rowBudget: WindowActivityPresentation.watchRowBudget).watchCaption == nil)
    }

    // MARK: stale

    @Test("a stale activity turns the +X weitere line red when the possibly überschritten window has no row")
    func staleHiddenWindowTurnsMoreRed() {
        let state = Self.state([Self.window("Küche", overdue: true), Self.window("Bad"), Self.window("Flur")])

        #expect(WindowActivityPresentation(contentState: state, rowBudget: 1, isStale: true).more?.isOverdue == true)
        #expect(WindowActivityPresentation(contentState: state, rowBudget: 1, isStale: false).more?.isOverdue == false)
        // With a row of its own the window shows "überschritten?" there, so the line stays as it is.
        #expect(WindowActivityPresentation(contentState: state, rowBudget: 2, isStale: true).more?.isOverdue == false)
    }

    @Test("a stale activity on the Watch shows the most urgent window as überschritten?")
    func staleWatchShowsPossiblyOverdue() {
        let state = Self.state([Self.window("Küche"), Self.window("Bad")])
        let presentation = WindowActivityPresentation(contentState: state, rowBudget: WindowActivityPresentation.watchRowBudget, isStale: true)

        #expect(presentation.watchCaption == WindowActivityPresentation.Caption(text: "überschritten?", isOverdue: true))
    }

    @Test("a stale activity on the Watch turns +X weitere offen red when the possibly überschritten window is hidden")
    func staleWatchHiddenWindowTurnsCaptionRed() {
        let state = Self.state([Self.window("Küche", overdue: true), Self.window("Bad")])
        let presentation = WindowActivityPresentation(contentState: state, rowBudget: WindowActivityPresentation.watchRowBudget, isStale: true)

        #expect(presentation.watchCaption == WindowActivityPresentation.Caption(text: "+1 weitere offen", isOverdue: true))
    }

    // MARK: outdoor temperature

    @Test("the outdoor temperature is shown in whole degrees", arguments: [
        (7.4, "7°"), (7.5, "8°"), (-0.4, "0°"), (-3.6, "-4°"), (21.0, "21°")
    ])
    func outdoorTemperatureInWholeDegrees(temperature: Double, expected: String) {
        let contentState = WindowContentState(sortedWindows: [Self.window("Küche")], outdoorTemperature: temperature)

        let presentation = WindowActivityPresentation(contentState: contentState, rowBudget: 3)

        #expect(presentation.outdoorTemperature == expected)
    }

    @Test("without a reading no outdoor temperature is shown")
    func noOutdoorTemperatureWithoutReading() {
        let presentation = WindowActivityPresentation(contentState: Self.state([Self.window("Küche")]), rowBudget: 3)

        #expect(presentation.outdoorTemperature == nil)
    }
}
