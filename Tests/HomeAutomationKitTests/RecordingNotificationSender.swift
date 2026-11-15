//
//  RecordingNotificationSender.swift
//  HomeAutomationKitTests
//

import Foundation
import HAModels

/// Records what leaves the server through ``NotificationSender``, so window tests can assert
/// on the Live Activity updates without APNS.
actor RecordingNotificationSender: NotificationSender {
    enum Event: Equatable {
        case liveActivity(WindowContentState)
        case end(activityType: String)
    }

    private(set) var events: [Event] = []

    /// The Live Activity content states in the order they were sent.
    var contentStates: [WindowContentState] {
        events.compactMap { event in
            if case let .liveActivity(state) = event { return state }
            return nil
        }
    }

    nonisolated func sendNotification(title: String, message: String, id: String) async throws {}

    nonisolated func clearNotification(id: String) async throws {}

    func startOrUpdateLiveActivity<ContentState: Encodable & Sendable>(contentState: ContentState, activityName: String) async {
        guard let state = contentState as? WindowContentState else { return }
        events.append(.liveActivity(state))
    }

    func endAllLiveActivities(ofActivityType activityType: String) async {
        events.append(.end(activityType: activityType))
    }
}
