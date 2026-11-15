//
//  WindowDynamicIslandViews.swift
//  FlowKit Controller
//

#if os(iOS)
import HAModels
import SwiftUI

// The Dynamic Island presentations of the window Live Activity (design 1c). Tint and content come
// only from the ``WindowActivityPresentation``, never from the current time. Nothing goes into the
// centre region, which sits over the camera.

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
    }
}

/// Compact leading and minimal: the window symbol with the number of offenen Fenster,
/// red once any window is überschritten.
public struct WindowIslandCountBadge: View {
    let openCount: Int
    let isAnyOverdue: Bool

    public init(contentState: WindowContentState, presentation: WindowActivityPresentation) {
        self.openCount = contentState.openCount
        self.isAnyOverdue = presentation.isAnyOverdue
    }

    public var body: some View {
        Label("\(openCount)", systemImage: "window.vertical.open")
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(isAnyOverdue ? Color.red : Color.primary)
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
                .foregroundStyle(presentation.isAnyOverdue ? Color.red : Color.primary)
                .frame(maxWidth: 52, alignment: .trailing)
        }
    }
}
#endif
