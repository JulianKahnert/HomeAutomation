// swift-tools-version: 6.2
import PackageDescription

// Floors are deliberately the newest majors: a prototype runs only on the author's
// machine, and the newest floor unlocks every current API. Adjust them per use case.
let package = Package(
    name: "HeizungDebugPrototype",
    platforms: [.macOS(.v26), .iOS(.v26)],
    dependencies: [
        // Pinned to a verified revision (2026-08-28): the in-process SnapshotTest API is
        // on main only — every tag through v0.9.4 has just the XCUITest-based variant.
        .package(url: "https://github.com/EmergeTools/SnapshotPreviews", revision: "856a1c1585e31d4113c019050d6d0712cf6ddadc"),
    ],
    targets: [
        // The design under iteration — compiles for macOS AND iOS, so Xcode Previews
        // work on both. Everything visual lives here.
        .target(name: "HeizungDebugPrototypeKit", swiftSettings: .prototype),
        // The macOS shell around it: live window with the Variants menu, and the
        // --screenshot capture mode. On iOS this target builds as an empty stub.
        .executableTarget(name: "HeizungDebugPrototype", dependencies: ["HeizungDebugPrototypeKit"], swiftSettings: .prototype),
        // Renders every #Preview to a PNG: SNAPSHOTS_EXPORT_DIR=$PWD/snapshots swift test —
        // macOS-only capture; hostless iOS test runners cannot render previews.
        .testTarget(
            name: "HeizungDebugPrototypePreviewTests",
            dependencies: [
                "HeizungDebugPrototypeKit",
                .product(name: "SnapshottingTests", package: "SnapshotPreviews"),
            ]
        ),
    ]
)

// The Xcode 27 app-template concurrency defaults: everything is MainActor unless it
// says otherwise, so prototype code needs no isolation annotations at all.
extension [SwiftSetting] {
    static var prototype: [SwiftSetting] {
        [
            .defaultIsolation(MainActor.self),
            .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            .enableUpcomingFeature("InferIsolatedConformances"),
        ]
    }
}
