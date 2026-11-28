//
//  MockNotificationSender.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 29.07.24.
//

import Foundation
import HAModels

final class MockNotificationSender: NotificationSender, @unchecked Sendable {
    func sendNotification(title: String, message: String, id: String, category: String?) async throws {}

    func startOrUpdateLiveActivity<ContentState: Encodable & Sendable>(contentState: ContentState, activityName: String, options: LiveActivityOptions) async {}

    func endAllLiveActivities<ContentState: Encodable & Sendable>(ofActivityType activityType: String, finalContentState: ContentState) async {}
}
