//
//  WindowProjection.swift
//

import Foundation
import HAModels

/// The window Live Activity as a projection: an automation without own state and without waiting. It reads the
/// deadline of every window and the outdoor temperature, computes the ``WindowContentState`` and hands it over
/// as a delivery.
///
/// - A deadline change sends at once; the change that makes a window überschritten carries the alert "Fenster schließen".
/// - While a window stays überschritten, `WindowOpen` repeats that alert once per Lüftungslimit through ``remind(of:using:)``.
/// - While a deadline exists, every 15 minutes a quiet update refreshes the outdoor temperature.
/// - With no window left, the Live Activity ends.
///
/// Its lane collapses nothing and waits for each run, so every change runs to its end in order, also while a send is slow.
public struct WindowProjection: Automatable {
    public static let defaultName = "WindowProjection"
    /// The quiet refresh runs on every clock tick whose minute is a multiple of this.
    public static let refreshMinutes = 15

    public var isActive = true
    public let name: String
    public var lanePolicy: LanePolicy { .runEach }

    public init(_ name: String = WindowProjection.defaultName) {
        self.name = name
    }

    public func shouldTrigger(with event: HomeEvent, using hm: HomeManagable) async throws -> Bool {
        switch event {
        case .change(let item):
            return item.entityId.characteristicType == .deadline
        case .time(let date):
            guard Calendar.current.component(.minute, from: date) % Self.refreshMinutes == 0 else { return false }
            return await hm.states(of: .deadline).contains { $0.deadline?.end != nil }
        case .sunrise, .sunset, .serverStarted, .configDeployed:
            return false
        }
    }

    public func execute(using hm: HomeManagable) async throws {
        let contentState = await hm.getWindowContentState()
        guard !contentState.windows.isEmpty else {
            log.debug("No open window left, ending the Live Activity")
            await hm.deliver(.endLiveActivities(activityType: WindowContentState.activityTypeName))
            return
        }

        var alert: LiveActivityOptions.Alert?
        var priority = LiveActivityOptions.Priority.low
        if case .change(let item)? = AutomationRunContext.event {
            priority = .high
            // The alert travels with the delivery that shows the window überschritten; a window closed meanwhile alerts not at all.
            if item.deadline?.isOverdue == true {
                alert = Self.closeAlert(for: item.entityId, in: contentState)
            }
        }
        let options = LiveActivityOptions(alert: alert, staleDate: contentState.staleDate, priority: priority)
        await hm.deliver(.liveActivity(contentState: contentState, activityName: WindowContentState.activityTypeName, options: options))
    }

    /// Sends the alert "Fenster schließen" again for a window that is still überschritten, with the current
    /// content state, like the update that made it überschritten. A window that is no longer überschritten
    /// (closed meanwhile) sends nothing, so a reminder never starts a Live Activity again.
    /// - Returns: Whether the reminder was handed over.
    @discardableResult
    public static func remind(of deadlineId: EntityId, using hm: HomeManagable) async throws -> Bool {
        let contentState = await hm.getWindowContentState()
        guard let alert = closeAlert(for: deadlineId, in: contentState) else { return false }
        // A run superseded meanwhile (the window closed) must not send the reminder after the end.
        try Task.checkCancellation()
        let options = LiveActivityOptions(alert: alert, staleDate: contentState.staleDate, priority: .high)
        await hm.deliver(.liveActivity(contentState: contentState, activityName: WindowContentState.activityTypeName, options: options))
        return true
    }

    /// The alert for the window of this deadline, `nil` when the window is not überschritten in the content state.
    private static func closeAlert(for deadlineId: EntityId, in contentState: WindowContentState) -> LiveActivityOptions.Alert? {
        guard let names = WindowContentState.window(of: deadlineId),
              let window = contentState.windows.first(where: { $0.id == WindowContentState.Window.id(room: names.room, name: names.name) }),
              window.isOverdue else { return nil }
        return LiveActivityOptions.Alert(title: "Fenster schließen", body: "\(window.room): \(window.name)")
    }

    public func triggerSummary(for event: HomeEvent, using hm: HomeManagable) async -> String? {
        if case .time = event { return "Quiet refresh" }
        return nil
    }
}
