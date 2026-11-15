#if os(macOS)
import AppKit
import HeizungDebugPrototypeKit
import SwiftUI

enum Screenshot {
    static func renderAllVariants(prefix: String) {
        // On screen for one beat: List is NSTableView-backed and only populates while
        // genuinely visible — an off-screen window stays empty.
        NSApplication.shared.setActivationPolicy(.accessory)
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: 120, y: 120), size: windowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        for variant in Variant.allCases {
            capture(PrototypeView(variant: variant), in: window, to: "\(prefix)-\(variant.rawValue).png")
        }
        window.contentView = nil
        window.orderOut(nil)
        exit(0)
    }

    private static func capture(_ view: some View, in window: NSWindow, to path: String) {
        window.contentView = NSHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)
        // One beat of the run loop so SwiftUI finishes layout before the capture.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.0))

        guard let content = window.contentView,
              let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
            fail("could not prepare the capture")
        }
        content.cacheDisplay(in: content.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            fail("could not encode the PNG")
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("wrote \(path)")
        } catch {
            fail("write failed: \(error)")
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}
#endif
