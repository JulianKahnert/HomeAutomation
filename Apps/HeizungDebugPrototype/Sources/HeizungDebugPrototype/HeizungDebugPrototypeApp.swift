#if os(macOS)
import AppKit
import HeizungDebugPrototypeKit
import SwiftUI

// Live window and screenshot capture share this size, so what the user sees is what
// the PNGs show. Match it to the surface being designed.
let windowSize = CGSize(width: 430, height: 900)

@main
enum Main {
    static func main() {
        // --screenshot [prefix]: render every variant offscreen and exit, so the
        // candidates can be compared without launching the app.
        if let flag = CommandLine.arguments.firstIndex(of: "--screenshot") {
            let prefix = CommandLine.arguments.indices.contains(flag + 1)
                ? CommandLine.arguments[flag + 1]
                : "prototype"
            Screenshot.renderAllVariants(prefix: prefix)
        } else {
            HeizungDebugPrototypeApp.main()
        }
    }
}

struct HeizungDebugPrototypeApp: App {
    // The last selection survives relaunches, so `swift run` reopens on the variant
    // under discussion.
    @AppStorage("variant") private var variantID = Variant.allCases[0].rawValue

    // A bare swift-run executable never becomes the active app on its own, so
    // every keystroke would stay with the terminal that launched it.
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    private var variant: Variant {
        Variant(rawValue: variantID) ?? Variant.allCases[0]
    }

    var body: some Scene {
        WindowGroup {
            PrototypeView(variant: variant)
                .onAppear { NSApp.activate() }
                .navigationTitle(variant.title)
        }
        .defaultSize(width: windowSize.width, height: windowSize.height)
        .commands {
            CommandMenu("Variants") {
                ForEach(Array(Variant.allCases.enumerated()), id: \.element) { index, candidate in
                    // A menu Toggle renders as a checkmarked item; ⌘1…⌘9 switch
                    // candidates while the window stays up.
                    Toggle(candidate.title, isOn: Binding(
                        get: { variantID == candidate.rawValue },
                        set: { isOn in
                            if isOn { variantID = candidate.rawValue }
                        }
                    ))
                    .keyboardShortcut(shortcut(for: index))
                }
            }
        }
    }

    private func shortcut(for index: Int) -> KeyboardShortcut? {
        guard index < 9 else { return nil }
        return KeyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
    }
}
#else
// The executable is macOS-only; this stub keeps whole-package iOS builds green.
@main
enum Main {
    static func main() {}
}
#endif
