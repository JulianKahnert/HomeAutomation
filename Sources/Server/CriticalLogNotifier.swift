//
//  CriticalLogNotifier.swift
//  HomeAutomation
//
//  Sends push notifications when CRITICAL-level log events occur.
//  Throttles to at most one notification per label per hour.
//

import Foundation
import HAModels
import Logging

/// Sends a push notification when a CRITICAL log event is recorded.
///
/// Register with ``configure(notificationSender:)`` after the push
/// infrastructure is ready. Until then, critical events are silently skipped.
actor CriticalLogNotifier {
    static let shared = CriticalLogNotifier()

    private var notificationSender: (any NotificationSender)?
    private var lastNotificationTime: [String: Date] = [:]
    private let throttleInterval: TimeInterval = 3600

    func configure(notificationSender: any NotificationSender) {
        self.notificationSender = notificationSender
    }

    func notify(label: String, message: String) async {
        guard let sender = notificationSender else { return }

        let now = Date()
        if let lastTime = lastNotificationTime[label],
           now.timeIntervalSince(lastTime) < throttleInterval {
            return
        }
        lastNotificationTime[label] = now

        do {
            try await sender.sendNotification(
                title: "Critical: \(label)",
                message: String(message.prefix(256)),
                id: "critical-\(label)"
            )
        } catch {
            // Avoid recursion: do not log at .critical here
        }
    }
}

/// LogHandler wrapper that forwards all calls to an underlying handler
/// and additionally triggers a push notification on `.critical` events.
struct CriticalNotifyingLogHandler: LogHandler {
    private var underlying: any LogHandler
    private let label: String

    var logLevel: Logger.Level {
        get { underlying.logLevel }
        set { underlying.logLevel = newValue }
    }

    var metadata: Logger.Metadata {
        get { underlying.metadata }
        set { underlying.metadata = newValue }
    }

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { underlying[metadataKey: key] }
        set { underlying[metadataKey: key] = newValue }
    }

    init(label: String, underlying: any LogHandler) {
        self.label = label
        self.underlying = underlying
    }

    func log(event: LogEvent) {
        underlying.log(event: event)

        if event.level == .critical {
            Task {
                await CriticalLogNotifier.shared.notify(
                    label: label,
                    message: "\(event.message)"
                )
            }
        }
    }
}
