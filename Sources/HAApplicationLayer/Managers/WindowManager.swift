//
//  WindowManager.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 15.03.25.
//

import HAModels
import Logging

actor WindowManager {
    private static let logger = Logger(label: "WindowManager")

    private let notificationSender: NotificationSender
    private var windowStateIsOpen: [EntityId: WindowOpenState] = [:]

    init(notificationSender: any NotificationSender) {
        self.notificationSender = notificationSender
    }

    /// Set newState to nil, if the window was closed
    func setWindowOpenState(entityId: EntityId, to newState: WindowOpenState?) async {
        windowStateIsOpen[entityId] = newState

        let windowStates = windowStateIsOpen.values.sorted(by: { $0.name < $1.name })
        if !windowStates.isEmpty {
            await startOrUpdateOpenWindowActivities(with: windowStates)
        } else {
            await notificationSender.endAllLiveActivities(ofActivityType: WindowContentState.activityTypeName)
        }
    }

    func getWindowStates() async -> [WindowOpenState] {
        var states = Array(windowStateIsOpen.values)
        states.sort { $0.name < $1.name }
        return states
    }

    private func startOrUpdateOpenWindowActivities(with windowStates: [WindowOpenState]) async {
        assert(!windowStates.isEmpty, "Use 'endAllOpenWindowActivities' when no window is opened")
        Self.logger.debug("Start or update open window activity")

        let states = windowStates.map { windowState in
            WindowContentState.WindowState(
                name: windowState.name,
                opened: windowState.opened,
                maxOpenDuration: windowState.maxOpenDuration)
        }
        let contentState = WindowContentState(windowStates: states)

        await notificationSender.startOrUpdateLiveActivity(contentState: contentState, activityName: WindowContentState.activityTypeName)
    }
}
