//
//  WindowOpenLiveActivityView.swift
//  FlowKit Controller
//
//  Created by Julian Kahnert on 06.03.25.
//

#if os(iOS)
import HAModels
import SwiftUI

/// The offenen Fenster as a compact list (design 1c): a header, at most `rowBudget` rows and a
/// "+X weitere" line. Used on the Lock Screen, in StandBy and on the Mac.
public struct WindowOpenLiveActivityView: View {
    let presentation: WindowActivityPresentation

    /// - Parameter isStale: The activity context's stale state; shows the first window not yet überschritten as "überschritten?".
    public init(contentState: WindowAttributes.ContentState,
                rowBudget: Int = WindowActivityPresentation.lockScreenRowBudget,
                isStale: Bool = false) {
        self.presentation = WindowActivityPresentation(contentState: contentState, rowBudget: rowBudget, isStale: isStale)
    }

    public var body: some View {
        // Spacing and margin from the prototype (design 1c), which measured 8 windows below 160 pt.
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "window.vertical.open")
                Text(presentation.header)
            }
            .font(.caption.weight(.semibold))

            ForEach(presentation.rows) { window in
                WindowActivityRow(window: window, isPossiblyOverdue: window.id == presentation.possiblyOverdueWindowId)
            }

            if let more = presentation.more {
                Text(more.text)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(more.isOverdue ? Color.red : Color.secondary)
            }
        }
        .padding(14)
    }
}

/// One offenes Fenster: Raum over window name, a progress bar towards the Fensterschließzeit,
/// and the countdown or the red overtime.
public struct WindowActivityRow: View {
    let window: WindowContentState.Window
    let isPossiblyOverdue: Bool

    /// - Parameter isPossiblyOverdue: Shows "überschritten?" instead of the window name, for a stale activity.
    public init(window: WindowContentState.Window, isPossiblyOverdue: Bool = false) {
        self.window = window
        self.isPossiblyOverdue = isPossiblyOverdue
    }

    public var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(window.room).font(.subheadline.weight(.semibold))
                if isPossiblyOverdue {
                    Text("überschritten?").font(.caption2).foregroundStyle(.red)
                } else {
                    Text(window.name).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .frame(width: 104, alignment: .leading)

            if window.isOverdue {
                // Full and red once the server marked the window überschritten.
                ProgressView(value: 1)
                    .tint(.red)
            } else {
                ProgressView(timerInterval: window.opened...window.closeBy, countsDown: false)
                    .labelsHidden()
                    .tint(.blue)
            }

            WindowActivityTimeLabel(window: window)
                .font(.subheadline.weight(.semibold))
                .frame(width: 50, alignment: .trailing)
        }
    }
}

/// The countdown to the Fensterschließzeit, or "+m:ss" in red once the server marked the window überschritten.
public struct WindowActivityTimeLabel: View {
    let window: WindowContentState.Window

    public init(window: WindowContentState.Window) {
        self.window = window
    }

    public var body: some View {
        Group {
            if window.isOverdue {
                Text("+\(Text(window.closeBy, style: .timer))")
                    .foregroundStyle(.red)
            } else {
                // The lower bound only anchors the system timer view; colour, order and text
                // come from the content state.
                Text(timerInterval: Date.now...max(Date.now, window.closeBy), countsDown: true)
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
    }
}

#Preview("8 offen") {
    let date = Date()
    let rooms = ["Küche", "Bad", "Büro", "Flur", "Schlafzimmer", "Wohnzimmer", "Kinderzimmer", "Keller"]
    let windows = rooms.enumerated().map { index, room in
        let opened = date.addingTimeInterval(Double(-index) * 60)
        return WindowContentState.Window(id: "window-\(room)-Fenster",
                                         name: "Fenster",
                                         room: room,
                                         opened: opened,
                                         closeBy: opened.addingTimeInterval(25 * 60),
                                         isOverdue: index == 0)
    }
    WindowOpenLiveActivityView(contentState: WindowContentState(windows: windows, openCount: windows.count, overdueCount: 1))
}
#endif
