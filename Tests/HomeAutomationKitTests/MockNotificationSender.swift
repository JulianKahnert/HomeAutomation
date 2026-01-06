//
//  MockNotificationSender.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 29.07.24.
//

import Foundation
import HAModels

final class MockNotificationSender: NotificationSender, @unchecked Sendable {
    func sendNotification(title: String, message: String) async throws {
        // Mock implementation - does nothing
    }

    func startOrUpdateLiveActivity<ContentState: Encodable & Sendable>(contentState: ContentState, activityName: String) async {
        // Mock implementation - does nothing
    }

    func endAllLiveActivities(ofActivityType activityType: String) async {
        // Mock implementation - does nothing
    }
}
