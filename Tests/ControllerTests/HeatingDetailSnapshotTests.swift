//
//  HeatingDetailSnapshotTests.swift
//  ControllerTests
//
//  Snapshots of the Heizung room detail: 24 h, 7 d, room without data and server not reachable,
//  light and dark, at iPhone (402 pt) and Mac (1120 pt) width. The dates come from
//  HeatingPreviewData (fixed "now"), the locale is de_DE and the time zone Europe/Berlin.
//
//  Re-record: delete the images in __Snapshots__/HeatingDetailSnapshotTests or run
//  `SNAPSHOT_TESTING_RECORD=all swift test --filter HeatingDetailSnapshotTests`.
//

#if os(macOS)
import AppKit
import ComposableArchitecture
@testable import Controller
import SnapshotTesting
import SwiftUI
import Testing

@MainActor
@Suite("Heating detail snapshots", .serialized)
struct HeatingDetailSnapshotTests {
    enum Device: String, CaseIterable {
        case iPhone, mac
        var layout: HeatingLayout { self == .iPhone ? .compact : .regular }
        var size: CGSize { self == .iPhone ? CGSize(width: 402, height: 900) : CGSize(width: 1_120, height: 760) }
    }

    enum Scenario: String, CaseIterable {
        case day24h, week7d, noData, offline
        var state: HeatingFeature.State {
            switch self {
            case .day24h: HeatingPreviewData.state("Bad OG")
            case .week7d: HeatingPreviewData.state("Schlafzimmer", range: .week)
            case .noData: HeatingPreviewData.state("Kaminzimmer")
            case .offline:
                {
                    var state = HeatingFeature.State()
                    state.error = "offline"
                    return state
                }()
            }
        }
    }

    private func screen(_ scenario: Scenario, _ device: Device, _ scheme: ColorScheme) -> some View {
        HeatingScreen(store: Store(initialState: scenario.state) { HeatingFeature() }, layout: device.layout)
            .frame(width: device.size.width, height: device.size.height)
            .background(Color(white: scheme == .dark ? 0.08 : 0.96))
            .environment(\.colorScheme, scheme)
            .environment(\.locale, Locale(identifier: "de_DE"))
            .environment(\.timeZone, TimeZone(identifier: "Europe/Berlin")!)
    }

    @Test("room detail renders as designed", arguments: Scenario.allCases)
    func detail(_ scenario: Scenario) {
        for device in Device.allCases {
            for scheme in [ColorScheme.light, .dark] {
                let name = "\(device.rawValue)-\(scheme == .dark ? "dark" : "light")"
                let view = NSHostingView(rootView: screen(scenario, device, scheme))
                view.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                assertSnapshot(
                    of: view,
                    as: .image(size: device.size),
                    named: name,
                    testName: "detail-\(scenario.rawValue)"
                )
            }
        }
    }

    @Test("the crosshair replaces the header and names the valve")
    func crosshair() {
        let detail = HeatingPreviewData.rooms.first { $0.id == "Küche" }!.detail(.day)
        let moment = HeatingPreviewData.now.addingTimeInterval(-6 * 3_600)
        for scheme in [ColorScheme.light, .dark] {
            let view = HeatingRoomDetailView(detail: detail, range: .constant(.day), crosshair: moment)
                .padding(16)
                .frame(width: 402, height: 520)
                .background(Color(white: scheme == .dark ? 0.08 : 0.96))
                .environment(\.colorScheme, scheme)
                .environment(\.locale, Locale(identifier: "de_DE"))
                .environment(\.timeZone, TimeZone(identifier: "Europe/Berlin")!)
            let hosting = NSHostingView(rootView: view)
            hosting.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            assertSnapshot(of: hosting, as: .image(size: CGSize(width: 402, height: 520)),
                           named: "iPhone-\(scheme == .dark ? "dark" : "light")", testName: "detail-crosshair")
        }
    }
}
#endif
