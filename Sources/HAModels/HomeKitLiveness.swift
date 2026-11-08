//
//  HomeKitLiveness.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 08.11.26.
//

import Foundation

/// Whether HomeKit is reachable end to end, from the server through the adapter into `homed`.
public enum HomeKitHealth: Equatable, Sendable {
    case healthy
    /// Not judged yet: the adapter has been disconnected for less than the grace period
    /// (server start, adapter reconnect).
    case unknown(reason: String)
    case degraded(reason: String)
}

/// Decides from passive signals whether HomeKit still works while the adapter link is up.
///
/// `homed` can drop the adapter app: HomeKit events stop and every command
/// fails with `HMErrorDomain Code=80`, but the WebSocket link stays up. This catches that state:
/// - no HomeKit event for longer than `maxEventGap` since the last event or (re)connect,
/// - a command failed with Code=80 and no event or successful command came after it,
/// - the adapter has been disconnected for longer than `disconnectGrace`.
public struct HomeKitLiveness: Sendable {
    /// The busiest sensors report every ~30 s; healthy gaps between two events stayed below 4 min
    /// over six days of adapter logs (Nov 2026), every longer gap was an outage.
    public static let defaultMaxEventGap: TimeInterval = 10 * 60
    public static let defaultDisconnectGrace: TimeInterval = 2 * 60

    private let maxEventGap: TimeInterval
    private let disconnectGrace: TimeInterval

    private var disconnectedSince: Date?
    private var connectedSince: Date?
    private var lastEventAt: Date?
    private var lastCommandSuccessAt: Date?
    private var lastAccessDeniedAt: Date?

    public init(startedAt: Date,
                maxEventGap: TimeInterval = Self.defaultMaxEventGap,
                disconnectGrace: TimeInterval = Self.defaultDisconnectGrace) {
        self.maxEventGap = maxEventGap
        self.disconnectGrace = disconnectGrace
        self.disconnectedSince = startedAt
    }

    public mutating func recordEvent(at date: Date) {
        lastEventAt = date
    }

    public mutating func recordCommandSuccess(at date: Date) {
        lastCommandSuccessAt = date
    }

    public mutating func recordCommandFailure(_ error: any Error, at date: Date) {
        guard Self.isAccessDenied(error) else { return }
        lastAccessDeniedAt = date
    }

    /// Mutating because it notes connection changes: a fresh connection gets a full `maxEventGap`
    /// before the missing events count against it.
    public mutating func evaluate(isConnected: Bool, at now: Date) -> HomeKitHealth {
        guard isConnected else {
            connectedSince = nil
            let since = disconnectedSince ?? now
            disconnectedSince = since
            guard now.timeIntervalSince(since) > disconnectGrace else {
                return .unknown(reason: "adapter not connected yet")
            }
            return .degraded(reason: "adapter not connected for \(Self.minutes(now.timeIntervalSince(since))) min")
        }

        disconnectedSince = nil
        let connectedSince = connectedSince ?? now
        self.connectedSince = connectedSince

        if let lastAccessDeniedAt,
           lastAccessDeniedAt > (lastEventAt ?? .distantPast),
           lastAccessDeniedAt > (lastCommandSuccessAt ?? .distantPast) {
            return .degraded(reason: "HomeKit refuses access (HMErrorDomain Code=80)")
        }

        let reference = max(lastEventAt ?? .distantPast, connectedSince)
        let gap = now.timeIntervalSince(reference)
        guard gap <= maxEventGap else {
            return .degraded(reason: "no HomeKit event for \(Self.minutes(gap)) min")
        }
        return .healthy
    }

    /// `HMErrorDomain Code=80` ("Handler does not support background access") reaches the server
    /// only as text: the adapter sends `String(describing: error)` through the StarActorSystem.
    static func isAccessDenied(_ error: any Error) -> Bool {
        let description = String(describing: error)
        let marker = "HMErrorDomain Code=80"
        var searchStart = description.startIndex
        while let range = description.range(of: marker, range: searchStart..<description.endIndex) {
            // `Code=801` is a different error
            guard range.upperBound < description.endIndex,
                  description[range.upperBound].isNumber else {
                return true
            }
            searchStart = range.upperBound
        }
        return false
    }

    private static func minutes(_ interval: TimeInterval) -> Int {
        Int(interval / 60)
    }
}
