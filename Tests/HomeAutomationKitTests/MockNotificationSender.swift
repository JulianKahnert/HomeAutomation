//
//  MockNotificationSender.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 29.07.24.
//

import Foundation
import HAModels

final class MockNotificationSender: NotificationSender, @unchecked Sendable {
    func sendNotification(title: String, message: String) async throws {}

    func sendNotification(title: String, message: String, id: String) async throws {}

    func clearNotification(id: String) async throws {}

    func startOrUpdateLiveActivity<ContentState: Encodable & Sendable>(contentState: ContentState, activityName: String) async {}

    func endAllLiveActivities(ofActivityType activityType: String) async {}
}
