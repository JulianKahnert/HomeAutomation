//
//  WindowActivityPresentation.swift
//  FlowKit Controller
//

import HAModels

/// What a window Live Activity surface shows, decided from the ``WindowContentState`` and a row budget alone.
///
/// It never reads the current time: order and überschritten come from the server. The only
/// exception is the stale state the system reports once the next Fensterschließzeit has passed.
public struct WindowActivityPresentation: Equatable, Sendable {
    /// Rows on the Lock Screen, in StandBy and on the Mac.
    public static let lockScreenRowBudget = 3
    /// Rows in the expanded Dynamic Island.
    public static let expandedRowBudget = 2

    /// The "+X weitere: Raum, Raum, …" line for the windows that do not fit.
    public struct More: Equatable, Sendable {
        public let text: String
        /// Red when a hidden window is überschritten.
        public let isOverdue: Bool
    }

    /// "<n> offen · <m> überschritten"
    public let header: String
    /// The windows that get a row, in server order.
    public let rows: [WindowContentState.Window]
    /// `nil` when every offene Fenster has a row.
    public let more: More?
    /// Tints the compact and minimal presentations.
    public let isAnyOverdue: Bool
    /// The window shown as "überschritten?": the activity went stale because the update marking it
    /// überschritten did not arrive. The stale date is the earliest Fensterschließzeit among windows
    /// not yet überschritten, so that is the first such window in server order.
    public let possiblyOverdueWindowId: String?

    public init(contentState: WindowContentState, rowBudget: Int, isStale: Bool = false) {
        let rows = Array(contentState.windows.prefix(max(rowBudget, 0)))
        let hidden = contentState.windows.dropFirst(rows.count)
        let hiddenCount = contentState.openCount - rows.count

        header = "\(contentState.openCount) offen · \(contentState.overdueCount) überschritten"
        self.rows = rows
        isAnyOverdue = contentState.overdueCount > 0
        possiblyOverdueWindowId = isStale ? contentState.windows.first { !$0.isOverdue }?.id : nil

        if hiddenCount > 0 {
            var rooms: [String] = []
            for room in hidden.map(\.room) where !rooms.contains(room) {
                rooms.append(room)
            }
            // Windows cut off by the server's cap are counted but not named.
            if contentState.openCount > contentState.windows.count {
                rooms.append("…")
            }
            let shownOverdueCount = rows.filter(\.isOverdue).count
            more = More(text: "+\(hiddenCount) weitere: \(rooms.joined(separator: ", "))",
                        isOverdue: contentState.overdueCount > shownOverdueCount)
        } else {
            more = nil
        }
    }
}
