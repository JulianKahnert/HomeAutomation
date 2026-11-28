//
//  NotificationSender.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 23.07.24.
//

import Foundation

public protocol NotificationSender: Sendable {
    /// Sends an alert notification tagged with a stable `id` used as `apns-collapse-id`
    /// and `threadIdentifier`, allowing the notification to be coalesced.
    ///
    /// - Parameter category: The notification category of the app, which gives the push its actions; `nil` for none.
    func sendNotification(title: String, message: String, id: String, category: String?) async throws

    /// Starts the Live Activity or updates the running one, delivered as `options` say.
    func startOrUpdateLiveActivity<ContentState: Encodable & Sendable>(contentState: ContentState,
                                                                       activityName: String,
                                                                       options: LiveActivityOptions) async
    /// Ends every running Live Activity of `activityType` on every device; `finalContentState` must decode as its content state.
    func endAllLiveActivities<ContentState: Encodable & Sendable>(ofActivityType activityType: String,
                                                                  finalContentState: ContentState) async
}

extension NotificationSender {
    public func sendNotification(title: String, message: String, id: String) async throws {
        try await sendNotification(title: title, message: message, id: id, category: nil)
    }
}
