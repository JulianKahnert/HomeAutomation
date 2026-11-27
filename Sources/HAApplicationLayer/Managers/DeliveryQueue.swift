//
//  DeliveryQueue.swift
//  HomeAutomationKit
//

import Foundation
import HAModels
import Logging

/// Sends ``Delivery`` values through the ``NotificationSender`` in the order they were handed over.
/// It knows no feature: the caller supplies the content.
actor DeliveryQueue {
    private static let logger = Logger(label: "DeliveryQueue")

    private let sender: any NotificationSender
    /// The send that was handed over last; the next one waits for it, also while an earlier send is slow.
    private var tail: Task<Void, Never>?
    /// When each push id was last sent, for rate limits of automations.
    private var pushDates: [String: Date] = [:]

    init(sender: any NotificationSender) {
        self.sender = sender
    }

    /// Returns when this delivery was sent or failed; a failure is logged.
    func deliver(_ delivery: Delivery) async {
        let previous = tail
        let task = Task { [self] in
            await previous?.value
            await send(delivery)
        }
        tail = task
        await task.value
    }

    func lastPushDate(id: String) -> Date? {
        pushDates[id]
    }

    private func send(_ delivery: Delivery) async {
        switch delivery {
        case let .push(title, message, id, category):
            do {
                Self.logger.debug("Sending notification", metadata: ["title": "\(title)", "id": "\(id)"])
                try await sender.sendNotification(title: title, message: message, id: id, category: category)
                pushDates[id] = Date()
            } catch {
                Self.logger.warning("Failed to send notification", metadata: ["id": "\(id)", "error": "\(error)"])
            }
        case .clearPush(let id):
            do {
                try await sender.clearNotification(id: id)
            } catch {
                Self.logger.warning("Failed to clear notification", metadata: ["id": "\(id)", "error": "\(error)"])
            }
        case let .liveActivity(contentState, activityName, options):
            await sender.startOrUpdateLiveActivity(contentState: contentState, activityName: activityName, options: options)
        case .endLiveActivities(let activityType):
            await sender.endAllLiveActivities(ofActivityType: activityType)
        }
    }
}
