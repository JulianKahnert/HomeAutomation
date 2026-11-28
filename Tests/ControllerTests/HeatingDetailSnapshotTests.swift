//
//  HeatingDetailSnapshotTests.swift
//  ControllerTests
//
//  Snapshots of the Heizung room detail: 24 h, 7 d, room without data and server not reachable,
//  light and dark, at iPhone (402 pt) and Mac (1120 pt) width. The dates come from
//  HeatingPreviewData (fixed "now"), the locale is en_US (the
//  English source text renders the same on every machine; a German locale in the environment is
//  honoured on the CI runner but not in a local test process) and the time zone Europe/Berlin.
//
//  Re-record: delete the images in __Snapshots__/HeatingDetailSnapshotTests or run
//  `SNAPSHOT_TESTING_RECORD=all swift test --filter HeatingDetailSnapshotTests`.
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
            case .day24h:
                return HeatingPreviewData.state("Bad OG")
            case .week7d:
                return HeatingPreviewData.state("Schlafzimmer", range: .week)
            case .noData:
                return HeatingPreviewData.state("Kaminzimmer")
            case .offline:
                var state = HeatingFeature.State()
                state.error = "offline"
                return state
            }
        }
    }

    private func screen(_ store: StoreOf<HeatingFeature>, _ device: Device, _ scheme: ColorScheme) -> some View {
        HeatingScreen(store: store, layout: device.layout)
            .frame(width: device.size.width, height: device.size.height)
            .background(Color(white: scheme == .dark ? 0.08 : 0.96))
            .environment(\.colorScheme, scheme)
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.timeZone, TimeZone(identifier: "Europe/Berlin")!)
    }

    @Test("room detail renders as designed", arguments: Scenario.allCases)
    func detail(_ scenario: Scenario) {
        for device in Device.allCases {
            for scheme in [ColorScheme.light, .dark] {
                let name = "\(device.rawValue)-\(scheme == .dark ? "dark" : "light")"
                let view = NSHostingView(rootView: screen(Store(initialState: scenario.state) { HeatingFeature() }, device, scheme))
                view.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                assertSnapshot(
                    of: view,
                    as: .image(size: device.size, scale: 2),
                    named: name,
                    testName: "detail-\(scenario.rawValue)"
                )
            }
        }
    }

    @Test("a reload in flight keeps the empty state on screen")
    func noRoomsWhileReloading() {
        var state = HeatingFeature.State()
        state.updatedAt = HeatingPreviewData.now
        let store = Store(initialState: state) {
            HeatingFeature()
        } withDependencies: {
            $0.serverClient.getHeatingOverview = { try await Task.never() }
            $0.serverClient.getFireplace = { try await Task.never() }
        }
        store.send(.refresh)
        let view = NSHostingView(rootView: screen(store, .iPhone, .light))
        view.appearance = NSAppearance(named: .aqua)
        assertSnapshot(of: view, as: .image(size: Device.iPhone.size, scale: 2), named: "iPhone-light", testName: "detail-noRoomsReloading")
    }

    @Test("the crosshair replaces the header and names the valve")
    func crosshair() {
        let detail = HeatingPreviewData.rooms.first { $0.id == "Küche" }!.detail(.day)
        let moment = HeatingPreviewData.now.addingTimeInterval(-6 * 3_600)
        for scheme in [ColorScheme.light, .dark] {
            let view = HeatingRoomDetailView(detail: detail, range: .constant(.day), crosshair: moment)
                .padding(16)
                .frame(width: 402, height: 600)
                .background(Color(white: scheme == .dark ? 0.08 : 0.96))
                .environment(\.colorScheme, scheme)
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.timeZone, TimeZone(identifier: "Europe/Berlin")!)
            let hosting = NSHostingView(rootView: view)
            hosting.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            assertSnapshot(of: hosting, as: .image(size: CGSize(width: 402, height: 600), scale: 2),
                           named: "iPhone-\(scheme == .dark ? "dark" : "light")", testName: "detail-crosshair")
        }
    }

    @Test("the crosshair in a fireplace band names the cause instead of plan and deviation")
    func crosshairInOffBand() {
        let detail = HeatingPreviewData.rooms.first { $0.id == "Küche" }!.detail(.day)
        let moment = HeatingPreviewData.moment(15, 18, 15)
        for scheme in [ColorScheme.light, .dark] {
            let view = HeatingRoomDetailView(detail: detail, range: .constant(.day), crosshair: moment)
                .padding(16)
                .frame(width: 402, height: 600)
                .background(Color(white: scheme == .dark ? 0.08 : 0.96))
                .environment(\.colorScheme, scheme)
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.timeZone, TimeZone(identifier: "Europe/Berlin")!)
            let hosting = NSHostingView(rootView: view)
            hosting.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            assertSnapshot(of: hosting, as: .image(size: CGSize(width: 402, height: 600), scale: 2),
                           named: "iPhone-\(scheme == .dark ? "dark" : "light")", testName: "detail-crosshairOffBand")
        }
    }

    @Test("a long press on the chart keeps the layout", arguments: HeatingPreviewData.rooms.map(\.id))
    func crosshairKeepsLayout(_ room: String) throws {
        let source = try #require(HeatingPreviewData.rooms.first { $0.id == room })
        for range in HeatingRange.allCases {
            let detail = source.detail(range)
            func height(_ crosshair: Date?) -> CGFloat {
                let view = HeatingRoomDetailView(detail: detail, range: .constant(range), crosshair: crosshair)
                    .frame(width: 370)
                    .environment(\.locale, Locale(identifier: "en_US"))
                    .environment(\.timeZone, TimeZone(identifier: "Europe/Berlin")!)
                return NSHostingView(rootView: view).fittingSize.height
            }
            let resting = height(nil)
            // Also inside each window or fireplace band, where the readout names the cause.
            let bands = HeatingChartData.offPeriods(detail.events, in: HeatingChartData.timeDomain(detail.samples))
                .map { Optional($0.range.lowerBound.addingTimeInterval($0.range.upperBound.timeIntervalSince($0.range.lowerBound) / 2)) }
            for moment in [detail.samples.first?.date, detail.samples.last?.date, HeatingPreviewData.now.addingTimeInterval(-3_600)] + bands {
                #expect(height(moment) == resting, "\(room) \(range): the crosshair at \(String(describing: moment)) changes the height")
            }
        }
    }
}
#endif
