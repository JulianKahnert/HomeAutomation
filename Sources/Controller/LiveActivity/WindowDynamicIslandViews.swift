//
//  WindowDynamicIslandViews.swift
//  FlowKit Controller
//

#if os(iOS)
import HAModels
import SwiftUI

// The Dynamic Island presentations (design 1c), driven only by ``WindowActivityPresentation``.
// Nothing goes into the centre region, which sits over the camera.

/// Expanded, leading: "<n> offen".
public struct WindowIslandExpandedLeading: View {
    let presentation: WindowActivityPresentation

    public init(presentation: WindowActivityPresentation) {
        self.presentation = presentation
    }

    public var body: some View {
        Label(presentation.openSummary, systemImage: "window.vertical.open")
            .labelStyle(.titleAndIcon)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            // The region starts in the island's rounded corner, which clipped the window symbol.
            .padding(.leading, 8)
    }
}

/// Expanded, trailing: a warning symbol with the number of überschrittenen Fenster, if any,
/// and the outdoor temperature, if there is a reading.
public struct WindowIslandExpandedTrailing: View {
    let presentation: WindowActivityPresentation

    public init(presentation: WindowActivityPresentation) {
        self.presentation = presentation
    }

    public var body: some View {
        HStack(spacing: 8) {
            if let overdueCount = presentation.overdueBadge {
                Label("\(overdueCount)", systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.red)
            }
            if let outdoorTemperature = presentation.outdoorTemperature {
                Text(outdoorTemperature)
                    .monospacedDigit()
            }
        }
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
        // The region ends in the island's rounded corner, which clipped the degree sign.
        .padding(.trailing, 8)
    }
}

/// Expanded, bottom: the rows within the expanded row budget and the "+X weitere" line.
public struct WindowIslandExpandedBottom: View {
    let presentation: WindowActivityPresentation

    public init(presentation: WindowActivityPresentation) {
        self.presentation = presentation
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            WindowActivityList(presentation: presentation)
        }
        // Keeps the last row out of the island's rounded bottom corners, which clipped its first letter.
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }
}

/// Compact leading and minimal: the window symbol with the number of offenen Fenster,
/// red once any window is überschritten.
public struct WindowIslandCountBadge: View {
    let openCount: Int
    let tint: Color

    public init(openCount: Int, tint: Color) {
        self.openCount = openCount
        self.tint = tint
    }

    public var body: some View {
        Label("\(openCount)", systemImage: "window.vertical.open")
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
    }
}

/// Compact trailing: the countdown or the overtime of the first window, red once any window is überschritten.
public struct WindowIslandCompactTrailing: View {
    let presentation: WindowActivityPresentation

    public init(presentation: WindowActivityPresentation) {
        self.presentation = presentation
    }

    public var body: some View {
        if let window = presentation.mostUrgent {
            WindowActivityTimeLabel(window: window)
                .font(.caption.weight(.semibold))
                .foregroundStyle(presentation.compactTint)
                .frame(maxWidth: 52, alignment: .trailing)
        }
    }
}

#Preview("Expanded") {
    let presentation = WindowActivityPresentation(contentState: .sample(overdueCount: 2),
                                                  rowBudget: WindowActivityPresentation.expandedRowBudget)
    VStack(spacing: 12) {
        HStack {
            WindowIslandExpandedLeading(presentation: presentation)
            Spacer()
            WindowIslandExpandedTrailing(presentation: presentation)
        }
        WindowIslandExpandedBottom(presentation: presentation)
    }
    .padding()
    .frame(width: 370)
    .background(.black, in: .rect(cornerRadius: 40))
    .environment(\.colorScheme, .dark)
}

#Preview("Compact and minimal") {
    let contentState = WindowContentState.sample(overdueCount: 2)
    let presentation = WindowActivityPresentation(contentState: contentState,
                                                  rowBudget: WindowActivityPresentation.expandedRowBudget)
    HStack(spacing: 24) {
        WindowIslandCountBadge(openCount: contentState.openCount, tint: presentation.compactTint)
        WindowIslandCompactTrailing(presentation: presentation)
        WindowIslandCountBadge(openCount: contentState.openCount, tint: presentation.compactTint)
    }
    .padding()
    .background(.black, in: .capsule)
    .environment(\.colorScheme, .dark)
}
#endif
