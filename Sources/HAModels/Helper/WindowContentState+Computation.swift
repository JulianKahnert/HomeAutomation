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

public extension WindowContentState {
    /// The content state from the stored deadline states: the one computation behind the Live Activity (memory of the
    /// `HomeManager`) and `GET /windowstates` (the database).
    /// - Parameters:
    ///   - deadlines: The current state of every deadline entity.
    ///   - history: The changes of one deadline entity, newest first.
    init(deadlines: [EntityStorageItem],
         history: @Sendable (EntityId) async -> [EntityStorageItem],
         outdoorTemperature: Double?) async {
        var windows: [(deadlineId: EntityId, deadline: Deadline, opened: Date)] = []
        for item in deadlines {
            guard let deadline = item.deadline, let end = deadline.end else { continue }
            let changes = await history(item.entityId)
            windows.append((item.entityId, deadline, WindowContentState.opened(end: end, history: changes) ?? item.timestamp))
        }
        self.init(windows: windows, outdoorTemperature: outdoorTemperature)
    }
}

public extension HomeManagable {
    /// The window Live Activity's content state, computed from the window deadlines and the outdoor temperature.
    func getWindowContentState() async -> WindowContentState {
        let deadlines = await states(of: .deadline)
        let outdoor = try? await getCurrentEntity(with: .outdoorTemperature).temperatureInC?.value
        return await WindowContentState(deadlines: deadlines,
                                        history: { await getFullEntityHistory(with: $0, limit: 50) },
                                        outdoorTemperature: outdoor)
    }
}

public extension StorageRepository {
    /// The content state of the open windows from the stored states, for the API (no running core needed).
    func windowContentState() async throws -> WindowContentState {
        let current = try await getAllCurrent()
        let deadlines = current.filter { $0.entityId.characteristicType == .deadline }
        let outdoor = current.first { $0.entityId == .outdoorTemperature }?.temperatureInC?.value
        return await WindowContentState(deadlines: deadlines,
                                        history: { (try? await self.getHistory(for: $0, startDate: nil, endDate: nil, cursor: nil, limit: 50)) ?? [] },
                                        outdoorTemperature: outdoor)
    }
}
