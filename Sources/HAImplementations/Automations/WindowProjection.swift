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
            // Only window deadlines: the fireplace question is a deadline too, but no window.
            return WindowContentState.window(of: item.entityId) != nil
        case .time(let date):
            guard Calendar.current.component(.minute, from: date) % Self.refreshMinutes == 0 else { return false }
            return await hm.states(of: .deadline).contains { $0.deadline?.end != nil && WindowContentState.window(of: $0.entityId) != nil }
        case .sunrise, .sunset, .serverStarted, .configDeployed:
            return false
        }
    }

    public func execute(using hm: HomeManagable) async throws {
        let contentState = await hm.getWindowContentState()
        guard !contentState.windows.isEmpty else {
            log.debug("No open window left, ending the Live Activity")
            await hm.deliver(.endLiveActivities(activityType: WindowContentState.activityTypeName, finalContentState: WindowContentState.empty))
            return
        }

        var alert: LiveActivityOptions.Alert?
        var priority = LiveActivityOptions.Priority.low
        if case .change(let item)? = AutomationRunContext.event {
            priority = .high
            // The alert travels with the delivery that shows the window überschritten; a window closed meanwhile alerts not at all.
            if item.deadline?.isOverdue == true,
               let names = WindowContentState.window(of: item.entityId),
               let window = contentState.windows.first(where: { $0.id == WindowContentState.Window.id(room: names.room, name: names.name) }),
               window.isOverdue {
                alert = LiveActivityOptions.Alert(title: "Fenster schließen", body: "\(window.room): \(window.name)")
            }
        }
        let options = LiveActivityOptions(alert: alert, staleDate: contentState.staleDate, priority: priority)
        await hm.deliver(.liveActivity(contentState: contentState, activityName: WindowContentState.activityTypeName, options: options))
    }

    public func triggerSummary(for event: HomeEvent, using hm: HomeManagable) async -> String? {
        if case .time = event { return "Quiet refresh" }
        return nil
    }
}
