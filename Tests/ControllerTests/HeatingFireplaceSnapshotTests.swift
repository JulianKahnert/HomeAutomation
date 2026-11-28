//
//  HeatingFireplaceSnapshotTests.swift
//  ControllerTests
//
//  Snapshots of the Heizung overview with the fireplace off and on (flame under the room name and the
//  orange area behind the bar of the rooms that follow it), light and dark, at iPhone (402 pt) and Mac
//  (1120 pt) width. A toolbar does not appear in a snapshot, so the real toolbar button and the subtitle
//  are drawn in a stand-in bar above the screen (like the prototype); the real toolbar item is checked
//  in the running app.
//
//  Re-record: delete the images in __Snapshots__/HeatingFireplaceSnapshotTests or run
//  `SNAPSHOT_TESTING_RECORD=all swift test --filter HeatingFireplaceSnapshotTests`.
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
@Suite("Heating fireplace snapshots", .serialized)
struct HeatingFireplaceSnapshotTests {
    private enum Device: String, CaseIterable {
        case iPhone, mac
        var layout: HeatingLayout { self == .iPhone ? .compact : .regular }
        var size: CGSize { self == .iPhone ? CGSize(width: 402, height: 900) : CGSize(width: 1_120, height: 760) }
    }

    /// The stand-in navigation bar: title, the subtitle the real one shows and the real toolbar button.
    private struct StandInBar: View {
        let fireplace: FireplaceState

        var body: some View {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Heating").font(.largeTitle.bold())
                    if let hint = HeatingFormat.fireplaceHint(fireplace, now: HeatingPreviewData.now) {
                        Text(hint).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                FireplaceToolbarButton(isOn: fireplace.isOn) {}
                    .labelStyle(.iconOnly)
                    .font(.body.weight(.medium))
                    .buttonStyle(.plain)
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: .circle)
                    .overlay(Circle().strokeBorder(Color.secondary.opacity(0.15)))
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    private func render(isOn: Bool, selected: String?, name: String, test: String) {
        for device in Device.allCases {
            for scheme in [ColorScheme.light, .dark] {
                let state = HeatingPreviewData.fireplaceState(on: isOn, selected: selected)
                let content = VStack(alignment: .leading, spacing: 0) {
                    StandInBar(fireplace: state.fireplace)
                    HeatingScreen(store: Store(initialState: state) { HeatingFeature() }, layout: device.layout)
                }
                .frame(width: device.size.width, height: device.size.height, alignment: .top)
                .background(Color(white: scheme == .dark ? 0.08 : 0.96))
                .environment(\.colorScheme, scheme)
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.timeZone, TimeZone(identifier: "Europe/Berlin")!)
                let view = NSHostingView(rootView: content)
                view.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                assertSnapshot(of: view, as: .image(size: device.size, scale: 2), named: "\(device.rawValue)-\(scheme == .dark ? "dark" : "light")", testName: test)
            }
        }
    }

    @Test("fireplace on: flame under the rooms that follow it, orange area, subtitle and filled flame")
    func fireplaceOn() {
        render(isOn: true, selected: "Küche", name: "on", test: "fireplace-on")
    }

    @Test("fireplace off: the same screen without flame, area and subtitle")
    func fireplaceOff() {
        render(isOn: false, selected: "Küche", name: "off", test: "fireplace-off")
    }
}
#endif
