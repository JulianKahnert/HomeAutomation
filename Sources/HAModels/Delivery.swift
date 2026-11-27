//
//  Delivery.swift
//  HomeAutomationKit
//

import Foundation

/// One push or Live Activity update, handed to the ``HomeManagable`` through ``HomeManagable/deliver(_:)``.
///
/// The caller supplies the full content, also the empty one that ends a Live Activity; the notification
/// adapter that sends it knows no feature.
public enum Delivery: Sendable {
    /// An alert push tagged with a stable `id` (`apns-collapse-id` and thread identifier).
    /// - Parameter category: The notification category of the app, which gives the push its actions; `nil` for none.
    case push(title: String, message: String, id: String, category: String? = nil)
    /// Starts the Live Activity or updates the running one.
    case liveActivity(contentState: any Encodable & Sendable, activityName: String, options: LiveActivityOptions)
    /// Ends every running Live Activity of this type.
    case endLiveActivities(activityType: String)
}
