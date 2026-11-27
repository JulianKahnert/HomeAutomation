//
//  RecordingNotificationSender.swift
//  HomeAutomationKitTests
//

import Foundation
import HAModels
@testable import HAApplicationLayer

/// Records what leaves the server through ``NotificationSender``, so window tests can assert
/// on the Live Activity updates without APNS.
actor RecordingNotificationSender: NotificationSender {
    struct Update: Equatable {
        let contentState: WindowContentState
        let options: LiveActivityOptions
    }

    enum Event: Equatable {
        case liveActivity(Update)
        case end(activityType: String)
        case notification(title: String, message: String, category: String?)
    }

    private(set) var events: [Event] = []

    /// The Live Activity updates in the order they were sent.
    var updates: [Update] {
        events.compactMap { event in
            if case let .liveActivity(update) = event { return update }
            return nil
        }
    }

    /// The Live Activity content states in the order they were sent.
    var contentStates: [WindowContentState] {
        updates.map(\.contentState)
    }

    func sendNotification(title: String, message: String, id: String, category: String?) async throws {
        events.append(.notification(title: title, message: message, category: category))
    }

    nonisolated func clearNotification(id: String) async throws {}

    func startOrUpdateLiveActivity<ContentState: Encodable & Sendable>(contentState: ContentState,
                                                                       activityName: String,
                                                                       options: LiveActivityOptions) async {
        guard let state = contentState as? WindowContentState else { return }
        events.append(.liveActivity(Update(contentState: state, options: options)))
    }

    func endAllLiveActivities(ofActivityType activityType: String) async {
        events.append(.end(activityType: activityType))
    }
}

extension WindowManager {
    /// A window manager that delivers through `sender`, like the one inside the `HomeManager`.
    init(notificationSender: any NotificationSender,
         now: @escaping @Sendable () -> Date = { Date() },
         outdoorTemperature: @escaping @Sendable () async -> Double? = { nil },
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        let queue = DeliveryQueue(sender: notificationSender)
        self.init(deliver: { await queue.deliver($0) }, now: now, outdoorTemperature: outdoorTemperature, sleep: sleep)
    }
}
