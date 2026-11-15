//
//  WindowManager.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 15.03.25.
//

import Foundation
import HAModels
import Logging

/// The single owner of the offenen Fenster and the only place that builds the Live Activity's
/// ``WindowContentState``.
actor WindowManager {
    private static let logger = Logger(label: "WindowManager")

    private let notificationSender: NotificationSender
    /// The current time. Injected so the überschritten transition and the stale date can be
    /// driven deterministically in tests.
    private let now: @Sendable () -> Date
    private var windowStateIsOpen: [EntityId: WindowOpenState] = [:]
    /// The offenen Fenster whose Fensterschließzeit has passed.
    private var overdueWindowIds: Set<String> = []

    init(notificationSender: any NotificationSender, now: @escaping @Sendable () -> Date = { Date() }) {
        self.notificationSender = notificationSender
        self.now = now
    }

    /// Set newState to nil, if the window was closed
    func setWindowOpenState(entityId: EntityId, to newState: WindowOpenState?) async {
        let action = newState != nil ? "opened" : "closed"
        Self.logger.info("Window \(action): \(entityId.name) (\(entityId.placeId))")
        // A newly opened window starts a new Lüftungslimit; a closed one is no longer überschritten.
        if let previous = windowStateIsOpen[entityId] {
            overdueWindowIds.remove(previous.id)
        }
        windowStateIsOpen[entityId] = newState

        let windowStates = getWindowStates()
        if !windowStates.isEmpty {
            Self.logger.info("Open windows: \(windowStates.map(\.name).joined(separator: ", "))")
            await startOrUpdateOpenWindowActivities(with: windowStates, alert: nil)
        } else {
            Self.logger.info("All windows closed, ending Live Activities")
            await notificationSender.endAllLiveActivities(ofActivityType: WindowContentState.activityTypeName)
        }
    }

    /// Marks an offenes Fenster überschritten once its Fensterschließzeit has passed and reminds the
    /// resident with a Live Activity alert. Does nothing for a closed window or one already überschritten,
    /// so every window alerts exactly once.
    func markWindowOverdue(entityId: EntityId) async {
        guard let window = windowStateIsOpen[entityId],
              overdueWindowIds.insert(window.id).inserted else {
            Self.logger.debug("Skip marking window überschritten: \(entityId.name) (\(entityId.placeId))")
            return
        }
        Self.logger.info("Window überschritten: \(entityId.name) (\(entityId.placeId))")

        let alert = LiveActivityOptions.Alert(title: "Fenster schließen", body: "\(window.room): \(window.name)")
        await startOrUpdateOpenWindowActivities(with: getWindowStates(), alert: alert)
    }

    /// The offenen Fenster in Live Activity order: überschritten first, then by Fensterschließzeit,
    /// window name as tiebreak.
    func getWindowStates() -> [WindowOpenState] {
        windowStateIsOpen.values.sorted { lhs, rhs in
            let lhsIsOverdue = isOverdue(lhs)
            let rhsIsOverdue = isOverdue(rhs)
            if lhsIsOverdue != rhsIsOverdue {
                return lhsIsOverdue
            }
            if lhs.closeBy != rhs.closeBy {
                return lhs.closeBy < rhs.closeBy
            }
            return lhs.name < rhs.name
        }
    }

    private func isOverdue(_ state: WindowOpenState) -> Bool {
        overdueWindowIds.contains(state.id)
    }

    private func startOrUpdateOpenWindowActivities(with windowStates: [WindowOpenState], alert: LiveActivityOptions.Alert?) async {
        assert(!windowStates.isEmpty, "Use 'endAllOpenWindowActivities' when no window is opened")
        Self.logger.debug("Start or update open window activity")

        let windows = windowStates.prefix(WindowContentState.maxWindowCount).map { state in
            WindowContentState.Window(id: state.id,
                                      name: state.name,
                                      room: state.room,
                                      opened: state.opened,
                                      closeBy: state.closeBy,
                                      isOverdue: isOverdue(state))
        }
        let contentState = WindowContentState(windows: Array(windows),
                                              openCount: windowStates.count,
                                              overdueCount: windowStates.filter(isOverdue).count)
        let options = LiveActivityOptions(alert: alert, staleDate: contentState.staleDate, priority: .high)

        await notificationSender.startOrUpdateLiveActivity(contentState: contentState,
                                                           activityName: WindowContentState.activityTypeName,
                                                           options: options)
    }
}
