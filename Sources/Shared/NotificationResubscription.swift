//
//  NotificationResubscription.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 08.11.26.
//

import Foundation

/// Decides which characteristic notification requests the adapter sends to HomeKit.
///
/// When `homed` deactivates the adapter app's connection, it drops
/// every notification registration of it, but the client-side `isNotificationEnabled` stays `true`.
/// A refresh that only compares against that flag then sends nothing and events never come back.
/// A forced resubscribe ignores the flag and registers every characteristic again.
public enum NotificationResubscription {
    /// The values to pass to `enableNotification(_:)`, in order; empty when nothing has to be sent.
    ///
    /// A forced resubscribe of a characteristic the client believes enabled disables it first, so
    /// HomeKit cannot skip the request as a no-op.
    public static func notificationRequests(shouldSubscribe: Bool, isNotificationEnabled: Bool, force: Bool) -> [Bool] {
        if force && shouldSubscribe {
            return isNotificationEnabled ? [false, true] : [true]
        }
        return shouldSubscribe != isNotificationEnabled ? [shouldSubscribe] : []
    }

    /// `HMErrorDomain Code=80` ("Handler does not support background access"): `homed` treats the
    /// app as background and refuses the request.
    public static func isBackgroundAccessDenied(_ error: any Error) -> Bool {
        let error = error as NSError
        return error.domain == "HMErrorDomain" && error.code == 80
    }
}

/// Collects resubscribe requests until the next entity refresh takes them.
///
/// The refresh itself is debounced elsewhere, so a burst of triggers (a manager reset, failing
/// commands) ends in one forced resubscribe that names every reason.
public actor ResubscribeRequests {
    private var reasons: [String] = []
    private var lastThrottledRequest: [String: ContinuousClock.Instant] = [:]

    public init() {}

    public func request(reason: String) {
        guard !reasons.contains(reason) else { return }
        reasons.append(reason)
    }

    /// Requests a resubscribe for `reason` unless the same reason was accepted less than
    /// `interval` before `now`.
    /// - Returns: Whether the request was accepted.
    public func request(reason: String, notWithin interval: Duration, now: ContinuousClock.Instant) -> Bool {
        if let last = lastThrottledRequest[reason], last.duration(to: now) < interval {
            return false
        }
        lastThrottledRequest[reason] = now
        request(reason: reason)
        return true
    }

    /// - Returns: The reasons requested since the last call, or nil when there was no request.
    public func take() -> [String]? {
        guard !reasons.isEmpty else { return nil }
        defer { reasons = [] }
        return reasons
    }
}
