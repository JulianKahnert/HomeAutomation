//
//  WindowContentState+Computation.swift
//  HAModels
//

import Foundation

public extension WindowContentState {
    /// When the window opened: the oldest of the newest changes that carry this `end`. A window that is closed and
    /// reopened into a deadline that ran before counts from the reopening; an overdue one keeps its start.
    /// - Parameter history: The deadline entity's changes, newest first.
    /// - Returns: `nil` when the history does not show it.
    static func opened(end: Date, history: [EntityStorageItem]) -> Date? {
        var opened: Date?
        for item in history {
            guard item.deadline?.end == end else { break }
            opened = item.timestamp
        }
        return opened
    }

    /// The window name of a deadline entity named `"<room>/<window>"`, `nil` for any other entity.
    static func window(of deadlineId: EntityId) -> (room: String, name: String)? {
        guard deadlineId.characteristicType == .deadline,
              let slash = deadlineId.name.firstIndex(of: "/") else { return nil }
        return (String(deadlineId.name[..<slash]), String(deadlineId.name[deadlineId.name.index(after: slash)...]))
    }

    /// The content state of the open windows: every deadline that is running or overdue is one offenes Fenster.
    /// Überschritten first, then by Fensterschließzeit, window name as tiebreak.
    /// - Parameter windows: The deadline of each window with the moment it opened.
    init(windows: [(deadlineId: EntityId, deadline: Deadline, opened: Date)], outdoorTemperature: Double?) {
        let contentWindows: [Window] = windows.compactMap { window in
            guard let end = window.deadline.end, let names = Self.window(of: window.deadlineId) else { return nil }
            return Window(id: Window.id(room: names.room, name: names.name),
                          name: names.name,
                          room: names.room,
                          opened: window.opened,
                          closeBy: end,
                          isOverdue: window.deadline.isOverdue)
        }
        let sorted = contentWindows.sorted { lhs, rhs in
            if lhs.isOverdue != rhs.isOverdue { return lhs.isOverdue }
            if lhs.closeBy != rhs.closeBy { return lhs.closeBy < rhs.closeBy }
            return lhs.name < rhs.name
        }
        self.init(sortedWindows: sorted, outdoorTemperature: outdoorTemperature)
    }
}

public extension HomeManagable {
    /// The window Live Activity's content state, computed from the window deadlines and the outdoor temperature.
    /// The one computation behind the Live Activity and `GET /windowstates`.
    func getWindowContentState() async -> WindowContentState {
        let deadlines = await states(of: CharacteristicsType.deadline.valueKind)
        var windows: [(deadlineId: EntityId, deadline: Deadline, opened: Date)] = []
        for item in deadlines {
            guard let deadline = item.deadline, let end = deadline.end else { continue }
            let history = await getFullEntityHistory(with: item.entityId, limit: 50)
            windows.append((item.entityId, deadline, WindowContentState.opened(end: end, history: history) ?? item.timestamp))
        }
        let outdoor = try? await getCurrentEntity(with: .outdoorTemperature).temperatureInC?.value
        return WindowContentState(windows: windows, outdoorTemperature: outdoor)
    }
}
