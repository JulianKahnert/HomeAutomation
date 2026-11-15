//
//  WindowActivityPresentation.swift
//  FlowKit Controller
//

import HAModels

/// What a window Live Activity surface shows, decided from the ``WindowContentState`` and a row budget alone.
///
/// It never reads the current time: order and überschritten come from the server.
public struct WindowActivityPresentation: Equatable, Sendable {
    /// Rows on the Lock Screen, in StandBy and on the Mac.
    public static let lockScreenRowBudget = 3
    /// Rows in the expanded Dynamic Island.
    public static let expandedRowBudget = 2
    /// The one window in the Watch Smart Stack (`.small` supplemental family).
    public static let watchRowBudget = 1

    /// The "+X weitere: Raum, Raum, …" line for the windows that do not fit.
    public struct More: Equatable, Sendable {
        public let text: String
        /// Red when a hidden window is überschritten.
        public let isOverdue: Bool
    }

    /// "<n> offen · <m> überschritten"
    public let header: String
    /// "<n> offen", leading in the expanded Dynamic Island.
    public let openSummary: String
    /// The number of überschrittenen Fenster beside the warning symbol, trailing in the expanded
    /// Dynamic Island; `nil` when no window is überschritten.
    public let overdueBadge: Int?
    /// The windows that get a row, in server order.
    public let rows: [WindowContentState.Window]
    /// The first window in server order, whose countdown or overtime the compact Dynamic Island shows.
    public let mostUrgent: WindowContentState.Window?
    /// `nil` when every offene Fenster has a row.
    public let more: More?
    /// The short "+X weitere offen" for the Watch, with the same count and colour as ``more``.
    public let moreCount: More?
    /// Tints the compact and minimal presentations.
    public let isAnyOverdue: Bool

    public init(contentState: WindowContentState, rowBudget: Int) {
        let rows = Array(contentState.windows.prefix(max(rowBudget, 0)))
        let hidden = contentState.windows.dropFirst(rows.count)
        let hiddenCount = contentState.openCount - rows.count

        header = "\(contentState.openCount) offen · \(contentState.overdueCount) überschritten"
        openSummary = "\(contentState.openCount) offen"
        overdueBadge = contentState.overdueCount > 0 ? contentState.overdueCount : nil
        self.rows = rows
        mostUrgent = contentState.windows.first
        isAnyOverdue = contentState.overdueCount > 0

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
            let isHiddenOverdue = contentState.overdueCount > shownOverdueCount
            more = More(text: "+\(hiddenCount) weitere: \(rooms.joined(separator: ", "))",
                        isOverdue: isHiddenOverdue)
            moreCount = More(text: "+\(hiddenCount) weitere offen", isOverdue: isHiddenOverdue)
        } else {
            more = nil
            moreCount = nil
        }
    }
}
