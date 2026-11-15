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

    init(notificationSender: any NotificationSender, now: @escaping @Sendable () -> Date = { Date() }) {
        self.notificationSender = notificationSender
        self.now = now
    }

    /// Set newState to nil, if the window was closed
    func setWindowOpenState(entityId: EntityId, to newState: WindowOpenState?) async {
        let action = newState != nil ? "opened" : "closed"
        Self.logger.info("Window \(action): \(entityId.name) (\(entityId.placeId))")
        windowStateIsOpen[entityId] = newState

        // Clear the delivered push notification for this specific window
        if newState == nil {
            try? await notificationSender.clearNotification(id: entityId.windowNotificationId)
        }

        let windowStates = getWindowStates()
        if !windowStates.isEmpty {
            Self.logger.info("Open windows: \(windowStates.map(\.name).joined(separator: ", "))")
            await startOrUpdateOpenWindowActivities(with: windowStates)
        } else {
            Self.logger.info("All windows closed, ending Live Activities")
            await notificationSender.endAllLiveActivities(ofActivityType: WindowContentState.activityTypeName)
        }
    }

    /// The offenen Fenster in Live Activity order: by Fensterschließzeit, window name as tiebreak.
    func getWindowStates() -> [WindowOpenState] {
        windowStateIsOpen.values.sorted { lhs, rhs in
            if lhs.closeBy != rhs.closeBy {
                return lhs.closeBy < rhs.closeBy
            }
            return lhs.name < rhs.name
        }
    }

    private func startOrUpdateOpenWindowActivities(with windowStates: [WindowOpenState]) async {
        assert(!windowStates.isEmpty, "Use 'endAllOpenWindowActivities' when no window is opened")
        Self.logger.debug("Start or update open window activity")

        let windows = windowStates.prefix(WindowContentState.maxWindowCount).map { state in
            WindowContentState.Window(id: state.id,
                                      name: state.name,
                                      room: state.room,
                                      opened: state.opened,
                                      closeBy: state.closeBy,
                                      isOverdue: false)
        }
        let contentState = WindowContentState(windows: Array(windows),
                                              openCount: windowStates.count,
                                              overdueCount: 0)

        await notificationSender.startOrUpdateLiveActivity(contentState: contentState, activityName: WindowContentState.activityTypeName)
    }
}
