//
//  Snapshotting+FixedScale.swift
//  ControllerTests
//
//  `.image(size:)` of SnapshotTesting renders an NSView at the backing scale factor of the main
//  screen, so a Retina Mac records 2x images, a 1x display or a CI runner 1x images, and the
//  references only match on the machine that recorded them. This strategy renders into a bitmap
//  with a fixed pixel size of `scale` times the point size, independent of any screen.
//
//  The rendering still depends on the macOS major version (fonts, controls, Charts), so record on
//  the version the "Swift Package Build & Test" job runs on. The tolerance absorbs the text
//  anti-aliasing differences between minor versions and the CI runner (about 1 % of the pixels).
//

#if os(macOS)
import AppKit
import SnapshotTesting

extension Snapshotting where Value == NSView, Format == NSImage {
    /// Renders the view at `size` points into an sRGB bitmap of `size * scale` pixels, independent of
    /// the screen. The Controller snapshots use `scale: 2`.
    static func image(size: CGSize, scale: CGFloat, precision: Float = 0.98, perceptualPrecision: Float = 0.98) -> Snapshotting {
        SimplySnapshotting.image(precision: precision, perceptualPrecision: perceptualPrecision).pullback { view in
            // The suites run on the main actor and `assertSnapshot` calls the pullback synchronously.
            MainActor.assumeIsolated {
                view.frame = CGRect(origin: .zero, size: size)
                view.layoutSubtreeIfNeeded()
                let bitmap = NSBitmapImageRep(
                    bitmapDataPlanes: nil,
                    pixelsWide: Int((size.width * scale).rounded()),
                    pixelsHigh: Int((size.height * scale).rounded()),
                    bitsPerSample: 8,
                    samplesPerPixel: 4,
                    hasAlpha: true,
                    isPlanar: false,
                    colorSpaceName: .calibratedRGB,
                    bytesPerRow: 0,
                    bitsPerPixel: 0
                )!.retagging(with: .sRGB)!
                bitmap.size = size
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let image = NSImage(size: size)
                image.addRepresentation(bitmap)
                return image
            }
        }
    }
}
#endif
