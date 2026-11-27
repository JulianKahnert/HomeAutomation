//
//  WindowContentState+Computation.swift
//  HAModels
//

import Foundation

public extension WindowContentState {
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
            // The window opened when its deadline started running; an overdue one keeps that start in the history.
            let history = await getEntityHistory(with: item.entityId, since: .distantPast)
            let started = history.filter { $0.deadline == .running(until: end) }.map(\.timestamp).min()
            windows.append((item.entityId, deadline, started ?? item.timestamp))
        }
        let outdoor = await states(of: CharacteristicsType.temperatureSensor.valueKind)
            .first { $0.entityId == .outdoorTemperature }?.temperatureInC?.value
        return WindowContentState(windows: windows, outdoorTemperature: outdoor)
    }
}
