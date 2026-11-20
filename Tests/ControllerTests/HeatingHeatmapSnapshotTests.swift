//
//  HeatingHeatmapSnapshotTests.swift
//  ControllerTests
//
//  Snapshots of the week heatmap card (preview data), light and dark, at the iPhone column width
//  (402 pt) and the Mac left column (420 pt), without and with a selected cell.
//
//  Re-record: delete the images in __Snapshots__/HeatingHeatmapSnapshotTests or run
//  `SNAPSHOT_TESTING_RECORD=all swift test --filter HeatingHeatmapSnapshotTests`.
//

#if os(macOS)
import AppKit
@testable import Controller
import HAModels
import SnapshotTesting
import SwiftUI
import Testing

@MainActor
@Suite("Heating heatmap snapshots", .serialized)
struct HeatingHeatmapSnapshotTests {
    private let devices: [(name: String, width: CGFloat)] = [("iPhone", 402), ("mac", 420)]

    private func render(selection: HeatingHeatmapView.Selection?, test: String) {
        let state = HeatingPreviewData.state("Bad OG")
        for device in devices {
            for scheme in [ColorScheme.light, .dark] {
                let size = CGSize(width: device.width, height: 240)
                let view = HeatingHeatmapView(rooms: state.rooms, cells: state.heatmap, selectedPlaceId: "Bad OG", selection: selection)
                    .padding(16)
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .background(Color(white: scheme == .dark ? 0.08 : 0.96))
                    .environment(\.colorScheme, scheme)
                    .environment(\.locale, Locale(identifier: "de_DE"))
                let host = NSHostingView(rootView: view)
                host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                assertSnapshot(of: host, as: .image(size: size), named: "\(device.name)-\(scheme == .dark ? "dark" : "light")", testName: test)
            }
        }
    }

    @Test("the week heatmap")
    func heatmap() {
        render(selection: nil, test: "heatmap")
    }

    @Test("a selected cell shows its value")
    func selected() {
        let day = HeatingPreviewData.state("Bad OG").heatmap.map(\.day).max()!
        render(selection: .init(placeId: "Bad OG", day: day, segment: 3), test: "heatmap-selected")
    }
}
#endif
