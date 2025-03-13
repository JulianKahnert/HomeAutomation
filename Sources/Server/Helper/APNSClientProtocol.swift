//
//  APNSClientProtocol.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 13.03.25.
//

import APNSCore

extension APNSClientProtocol {
    /// Starts a live activity notification.
    ///
    /// - Parameters:
    ///   - notification: The notification to send.
    ///
    ///   - deviceToken: The hexadecimal bytes use to send live activity notification. Your app receives the bytes for this activity token
    ///    from `pushTokenUpdates` async property of a live activity.
    ///
    ///
    ///   - logger: The logger to use for sending this notification.
    @discardableResult
    @inlinable
    public func sendStartLiveActivityNotification<Attributes: Encodable, ContentState: Encodable>(
        _ notification: APNSStartLiveActivityNotification<Attributes, ContentState>,
        deviceToken: String
    ) async throws -> APNSResponse {
        let request = APNSRequest(
            message: notification,
            deviceToken: deviceToken,
            pushType: .liveactivity,
            expiration: notification.expiration,
            priority: notification.priority,
            apnsID: notification.apnsID,
            topic: notification.topic,
            collapseID: nil
        )
        return try await send(request)
    }
}
