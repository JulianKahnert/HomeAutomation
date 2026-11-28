//
//  DeliveryQueue.swift
//  HomeAutomationKit
//

import Foundation
import HAModels
import Shared

/// Sends ``Delivery`` values through the ``NotificationSender`` in the order they were handed over.
/// It knows no feature: the caller supplies the content.
actor DeliveryQueue: Log {
    private let sender: any NotificationSender
    /// The send that was handed over last; the next one waits for it, also while an earlier send is slow.
    private var tail: Task<Void, Never>?
    /// When each push id was last sent, for rate limits of automations.
    private var pushDates: [String: Date] = [:]
    /// How many deliveries were handed over so far; lets a test wait until one reached the queue.
    private(set) var handedOver = 0

    /// How long one send may take before the next delivery goes ahead without it.
    private let sendTimeout: Duration

    init(sender: any NotificationSender, sendTimeout: Duration = .seconds(30)) {
        self.sender = sender
        self.sendTimeout = sendTimeout
    }

    /// Returns when this delivery was sent or failed; a failure is logged.
    func deliver(_ delivery: Delivery) async {
        handedOver += 1
        let previous = tail
        let task = Task { [self] in
            await previous?.value
            // An APNS send has no deadline of its own: a stalled connection would hold every later delivery and
            // the lane of every run that waits for one. The send that is given up may still arrive late.
            do {
                try await raceTimeout(sendTimeout, timeoutError: { DeliveryTimeout() }, operation: { await self.send(delivery) })
            } catch {
                log.warning("Delivery timed out, the next one goes ahead", metadata: ["delivery": "\(delivery)"])
            }
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
                log.debug("Sending notification", metadata: ["title": "\(title)", "id": "\(id)"])
                try await sender.sendNotification(title: title, message: message, id: id, category: category)
                pushDates[id] = Date()
            } catch {
                log.warning("Failed to send notification", metadata: ["id": "\(id)", "error": "\(error)"])
            }
        case let .liveActivity(contentState, activityName, options):
            await sender.startOrUpdateLiveActivity(contentState: contentState, activityName: activityName, options: options)
        case .endLiveActivities(let activityType):
            await sender.endAllLiveActivities(ofActivityType: activityType)
        }
    }
}

private struct DeliveryTimeout: Error {}
