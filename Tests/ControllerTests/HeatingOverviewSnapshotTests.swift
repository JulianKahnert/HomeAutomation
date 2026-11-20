//
//  HeatingOverviewSnapshotTests.swift
//  ControllerTests
//
//  Snapshots of the Heizung overview: bars only (iPhone: one column; Mac: two columns with the
//  placeholder), a room opened next to or below the bars, and the bars with an info bubble, a bar
//  running off the end and a hatched "?" bar, light and dark, at iPhone (402 pt) and Mac (1120 pt) width.
//
//  Re-record: delete the images in __Snapshots__/HeatingOverviewSnapshotTests or run
//  `SNAPSHOT_TESTING_RECORD=all swift test --filter HeatingOverviewSnapshotTests`.
//

#if os(macOS)
import AppKit
import ComposableArchitecture
@testable import Controller
import HAModels
import SnapshotTesting
import SwiftUI
import Testing

@MainActor
@Suite("Heating overview snapshots", .serialized)
struct HeatingOverviewSnapshotTests {
    enum Device: String, CaseIterable {
        case iPhone, mac
        var layout: HeatingLayout { self == .iPhone ? .compact : .regular }
        var size: CGSize { self == .iPhone ? CGSize(width: 402, height: 900) : CGSize(width: 1_120, height: 760) }
    }

    private func room(_ name: String, ist: Double?, plan: Double = 21) -> HeatingOverviewRoom {
        HeatingOverviewRoom(placeId: name, name: name, shortName: name, ist: ist, sollPlan: plan, istSource: .roomSensor("Eve Room"))
    }

    private func render(_ content: some View, _ size: CGSize, _ scheme: ColorScheme, name: String, test: String) {
        let styled = content
            .frame(width: size.width, height: size.height)
            .background(Color(white: scheme == .dark ? 0.08 : 0.96))
            .environment(\.colorScheme, scheme)
            .environment(\.locale, Locale(identifier: "de_DE"))
            .environment(\.timeZone, TimeZone(identifier: "Europe/Berlin")!)
        let view = NSHostingView(rootView: styled)
        view.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        assertSnapshot(of: view, as: .image(size: size), named: "\(name)-\(scheme == .dark ? "dark" : "light")", testName: test)
    }

    @Test("overview without a selection: bars on iPhone, bars and placeholder on Mac")
    func overview() {
        for device in Device.allCases {
            for scheme in [ColorScheme.light, .dark] {
                let screen = HeatingScreen(store: Store(initialState: HeatingPreviewData.state()) { HeatingFeature() }, layout: device.layout)
                render(screen, device.size, scheme, name: device.rawValue, test: "overview")
            }
        }
    }

    @Test("a selected room opens below the bars on iPhone and right of them on Mac")
    func selected() {
        for device in Device.allCases {
            for scheme in [ColorScheme.light, .dark] {
                let screen = HeatingScreen(store: Store(initialState: HeatingPreviewData.state("Bad OG")) { HeatingFeature() }, layout: device.layout)
                render(screen, device.size, scheme, name: device.rawValue, test: "overview-selected")
            }
        }
    }

    @Test("all rooms in plan")
    func allInPlan() {
        var state = HeatingFeature.State()
        state.rooms = [room("Bad", ist: 21.2), room("Küche", ist: 20.8), room("Flur", ist: 21)]
        for scheme in [ColorScheme.light, .dark] {
            let screen = HeatingScreen(store: Store(initialState: state) { HeatingFeature() }, layout: .compact)
            render(screen, CGSize(width: 402, height: 420), scheme, name: "iPhone", test: "overview-allInPlan")
        }
    }

    @Test("info bubble, a bar beyond 3 K running off the end and a hatched bar")
    func bubbleAndRunOff() {
        let rooms = HeatingFeature.sorted([room("Bad OG", ist: 16.5), room("Küche", ist: 22.4), room("Büro", ist: 20.7),
                                           room("Flur", ist: 23.5), room("Keller", ist: nil)])
        for scheme in [ColorScheme.light, .dark] {
            let view = HeatingOverviewView(rooms: rooms, headline: HeatingFeature.headlineParts(for: rooms), updatedAt: HeatingPreviewData.now, selectedPlaceId: "Büro",
                                           hoveredPlaceId: "Küche") { _ in }
                .padding(16)
            render(view, CGSize(width: 402, height: 340), scheme, name: "iPhone", test: "overview-bubble")
        }
    }
}
#endif
