//
//  NotificationSender.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 23.07.24.
//

import Foundation

public protocol NotificationSender: Sendable {
    /// Sends an alert notification tagged with a stable `id` used as `apns-collapse-id`
    /// and `threadIdentifier`, allowing the notification to be coalesced and later cleared
    /// individually via ``clearNotification(id:)``.
    func sendNotification(title: String, message: String, id: String) async throws

    /// Sends a `content-available` background push so the client can remove a previously
    /// delivered notification identified by `id` (matched via `threadIdentifier`).
    func clearNotification(id: String) async throws

    func startOrUpdateLiveActivity<ContentState: Encodable & Sendable>(contentState: ContentState, activityName: String) async
    func endAllLiveActivities(ofActivityType activityType: String) async
}
