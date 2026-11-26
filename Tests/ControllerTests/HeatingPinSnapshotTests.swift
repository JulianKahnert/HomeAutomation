//
//  HeatingPinSnapshotTests.swift
//  ControllerTests
//
//  Snapshots of the event pins in the room detail: several pins in two rows, a "+n" pin, areas for
//  window and fireplace, the reason as inline card (iPhone) and as popover content (Mac), light and dark.
//  A real popover is a separate window and not part of a hosting view snapshot, so Mac shows the selected
//  pin and the card content apart.
//
//  Re-record: delete the images in __Snapshots__/HeatingPinSnapshotTests or run
//  `SNAPSHOT_TESTING_RECORD=all swift test --filter HeatingPinSnapshotTests`.
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
@Suite("Heating pin snapshots", .serialized)
struct HeatingPinSnapshotTests {
    enum Device: String, CaseIterable {
        case iPhone, mac
        var layout: HeatingLayout { self == .iPhone ? .compact : .regular }
        var size: CGSize { self == .iPhone ? CGSize(width: 402, height: 900) : CGSize(width: 1_120, height: 760) }
    }

    /// The selection is picked from the pins as `device` stacks them before the chart measured itself.
    private func state(_ range: HeatingRange, room: String, select: Select, on device: Device = .iPhone) -> HeatingFeature.State {
        var state = HeatingPreviewData.state(room, range: range)
        let detail = state.detail!
        let slots = HeatingSollIstChart.slots(events: detail.events, samples: detail.samples, range: range, plotWidth: device.layout.plotWidthEstimate)
        switch select {
        case .none: break
        case .group: state.selectedPinId = slots.first { $0.badge != nil }?.id
        case .single: state.selectedPinId = slots.first { $0.events[0].source == .observed && $0.badge == nil }?.id
        }
        return state
    }

    enum Select { case none, group, single }

    private func screen(_ state: HeatingFeature.State, _ device: Device, _ scheme: ColorScheme) -> some View {
        HeatingScreen(store: Store(initialState: state) { HeatingFeature() }, layout: device.layout)
            .frame(width: device.size.width, height: device.size.height)
            .background(Color(white: scheme == .dark ? 0.08 : 0.96))
            .environment(\.colorScheme, scheme)
            .environment(\.locale, Locale(identifier: "de_DE"))
            .environment(\.timeZone, TimeZone(identifier: "Europe/Berlin")!)
    }

    private func record<V: View>(_ view: V, size: CGSize, scheme: ColorScheme, name: String, test: String) {
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        assertSnapshot(of: hosting, as: .image(size: size, scale: 2), named: "\(name)-\(scheme == .dark ? "dark" : "light")", testName: test)
    }

    @Test("several pins in two rows, a +n pin and the areas of window and fireplace")
    func pins() {
        for device in Device.allCases {
            for scheme in [ColorScheme.light, .dark] {
                record(screen(state(.day, room: "Küche", select: .none), device, scheme), size: device.size, scheme: scheme, name: device.rawValue, test: "pins-day24h")
            }
        }
    }

    @Test("the +n pin selected: its list as inline card on iPhone")
    func group() {
        for device in Device.allCases {
            for scheme in [ColorScheme.light, .dark] {
                record(screen(state(.day, room: "Küche", select: .group, on: device), device, scheme), size: device.size, scheme: scheme, name: device.rawValue, test: "pins-group")
            }
        }
    }

    @Test("one pin selected: its reason as inline card on iPhone")
    func single() {
        for scheme in [ColorScheme.light, .dark] {
            record(screen(state(.day, room: "Küche", select: .single), .iPhone, scheme), size: Device.iPhone.size, scheme: scheme, name: "iPhone", test: "pins-single")
        }
    }

    @Test("over a week the plan pins are left out")
    func week() {
        for device in Device.allCases {
            for scheme in [ColorScheme.light, .dark] {
                record(screen(state(.week, room: "Schlafzimmer", select: .none), device, scheme), size: device.size, scheme: scheme, name: device.rawValue, test: "pins-week7d")
            }
        }
    }

    @Test("the content of the Mac popover")
    func popoverContent() {
        let events = Array(HeatingPreviewData.kitchenEvents[5...7])
        for scheme in [ColorScheme.light, .dark] {
            let view = HeatingPinCard(events: events, inPopover: true)
                .frame(width: 260)
                .background(Color(white: scheme == .dark ? 0.16 : 1))
                .environment(\.colorScheme, scheme)
                .environment(\.locale, Locale(identifier: "de_DE"))
                .environment(\.timeZone, TimeZone(identifier: "Europe/Berlin")!)
            record(view, size: CGSize(width: 260, height: 260), scheme: scheme, name: "mac", test: "pins-popover")
        }
    }
}
#endif
