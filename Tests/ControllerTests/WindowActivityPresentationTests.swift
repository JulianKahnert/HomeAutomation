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
        WindowContentState.Window(id: "window-\(room)-Fenster",
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

    @Test("the compact and minimal tint is red once any window is überschritten")
    func compactTintFollowsOverdueCount() {
        #expect(WindowActivityPresentation(contentState: Self.state([Self.window("Küche")]), rowBudget: 1).isAnyOverdue == false)

        let overdueBeyondCap = Self.state([Self.window("Küche")], openCount: 25, overdueCount: 1)
        #expect(WindowActivityPresentation(contentState: overdueBeyondCap, rowBudget: 1).isAnyOverdue == true)
    }
    @Test("the Watch shows the most urgent window and +X weitere offen for the rest")
    func watchShowsFirstWindowAndCountsTheRest() {
        let presentation = WindowActivityPresentation(contentState: Self.state(Self.eightRooms.map { Self.window($0) }),
                                                      rowBudget: WindowActivityPresentation.watchRowBudget)

        #expect(presentation.rows.map(\.room) == ["Küche"])
        #expect(presentation.moreCount?.text == "+7 weitere offen")
        #expect(presentation.moreCount?.isOverdue == false)
    }

    @Test("the Watch's +X weitere offen counts windows beyond the server's cap and turns red for a hidden überschritten window")
    func watchMoreCountUsesFullCounts() {
        let capped = Self.state([Self.window("Küche"), Self.window("Bad", overdue: true)], openCount: 23, overdueCount: 1)
        let presentation = WindowActivityPresentation(contentState: capped, rowBudget: WindowActivityPresentation.watchRowBudget)

        #expect(presentation.moreCount?.text == "+22 weitere offen")
        #expect(presentation.moreCount?.isOverdue == true)
    }

    @Test("a single window on the Watch has no +X weitere offen")
    func watchSingleWindowHasNoMoreCount() {
        let presentation = WindowActivityPresentation(contentState: Self.state([Self.window("Küche")]),
                                                      rowBudget: WindowActivityPresentation.watchRowBudget)

        #expect(presentation.moreCount == nil)
    }
}
