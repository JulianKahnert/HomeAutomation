//
//  WindowActivityPresentation.swift
//  FlowKit Controller
//

import HAModels
import SwiftUI

/// What a window Live Activity surface shows, decided from the ``WindowContentState``, a row budget and
/// the system's stale state alone; it never reads the current time.
public struct WindowActivityPresentation: Equatable, Sendable {
    /// Rows on the Lock Screen, in StandBy and on the Mac.
    public static let lockScreenRowBudget = 3
    /// Rows in the expanded Dynamic Island.
    public static let expandedRowBudget = 2
    /// The one window in the Watch Smart Stack (`.small` supplemental family).
    public static let watchRowBudget = 1

    /// A line of text, red when it stands for an overdue window.
    public struct Caption: Equatable, Sendable {
        public let text: String
        public let isOverdue: Bool

        public var color: Color {
            isOverdue ? .red : .secondary
        }
    }

    /// "<n> open · <m> overdue"
    public let header: String
    /// "<n> open", leading in the expanded Dynamic Island.
    public let openSummary: String
    /// The number of overdue windows beside the warning symbol, trailing in the expanded
    /// Dynamic Island; `nil` when no window is overdue.
    public let overdueBadge: Int?
    /// The outdoor temperature in whole degrees ("7°"), right in the Lock Screen header and trailing
    /// in the expanded Dynamic Island; `nil` without a reading.
    public let outdoorTemperature: String?
    /// The windows that get a row, in server order.
    public let rows: [WindowContentState.Window]
    /// The first window in server order, whose countdown or overtime the compact Dynamic Island shows.
    public let mostUrgent: WindowContentState.Window?
    /// The "+X more: room, room, …" line; red when a window without a row is overdue or
    /// possibly overdue. `nil` when every open window has a row.
    public let more: Caption?
    /// The line below the Watch's window: "overdue?", else "+X more open" coloured like
    /// ``more``, else the window name. `nil` without a window.
    public let watchCaption: Caption?
    public let isAnyOverdue: Bool
    /// The window shown as "overdue?" in a stale activity: the first window not yet overdue,
    /// whose closing time is the stale date.
    public let possiblyOverdueWindowId: String?

    /// Tints the compact and minimal presentations.
    public var compactTint: Color {
        isAnyOverdue ? .red : .primary
    }

    public init(contentState: WindowContentState, rowBudget: Int, isStale: Bool = false) {
        let rows = Array(contentState.windows.prefix(max(rowBudget, 0)))
        let hidden = contentState.windows.dropFirst(rows.count)
        let hiddenCount = contentState.openCount - rows.count

        header = String(localized: "\(contentState.openCount) open · \(contentState.overdueCount) overdue", bundle: .module)
        openSummary = String(localized: "\(contentState.openCount) open", bundle: .module)
        overdueBadge = contentState.overdueCount > 0 ? contentState.overdueCount : nil
        outdoorTemperature = contentState.outdoorTemperature.map { "\(Int($0.rounded()))°" }
        self.rows = rows
        mostUrgent = contentState.windows.first
        isAnyOverdue = contentState.overdueCount > 0
        let possiblyOverdueWindowId = isStale ? contentState.windows.first { !$0.isOverdue }?.id : nil
        self.possiblyOverdueWindowId = possiblyOverdueWindowId

        watchCaption = contentState.windows.first.map { window in
            Self.watchCaption(for: window, contentState: contentState, possiblyOverdueWindowId: possiblyOverdueWindowId, isStale: isStale)
        }

        guard hiddenCount > 0 else {
            more = nil
            return
        }
        var rooms: [String] = []
        for room in hidden.map(\.room) where !rooms.contains(room) {
            rooms.append(room)
        }
        // Windows cut off by the server's cap are counted but not named.
        if contentState.openCount > contentState.windows.count {
            rooms.append("…")
        }
        let isMoreOverdue = Self.isHiddenOverdue(rows: rows,
                                                 contentState: contentState,
                                                 possiblyOverdueWindowId: possiblyOverdueWindowId,
                                                 isStale: isStale)
        more = Caption(text: String(localized: "+\(hiddenCount) more: \(rooms.joined(separator: ", "))", bundle: .module), isOverdue: isMoreOverdue)
    }

    /// Whether a window without a row is overdue, or possibly overdue in a stale activity.
    private static func isHiddenOverdue(rows: [WindowContentState.Window],
                                        contentState: WindowContentState,
                                        possiblyOverdueWindowId: String?,
                                        isStale: Bool) -> Bool {
        let isHiddenPossiblyOverdue = isStale && !rows.contains { $0.id == possiblyOverdueWindowId }
        return contentState.overdueCount > rows.filter(\.isOverdue).count || isHiddenPossiblyOverdue
    }

    private static func watchCaption(for window: WindowContentState.Window,
                                     contentState: WindowContentState,
                                     possiblyOverdueWindowId: String?,
                                     isStale: Bool) -> Caption {
        if window.id == possiblyOverdueWindowId {
            return Caption(text: String(localized: "overdue?", bundle: .module), isOverdue: true)
        }
        guard contentState.openCount > 1 else {
            return Caption(text: window.name, isOverdue: false)
        }
        let isOverdue = isHiddenOverdue(rows: [window],
                                        contentState: contentState,
                                        possiblyOverdueWindowId: possiblyOverdueWindowId,
                                        isStale: isStale)
        return Caption(text: String(localized: "+\(contentState.openCount - 1) more open", bundle: .module), isOverdue: isOverdue)
    }
}
