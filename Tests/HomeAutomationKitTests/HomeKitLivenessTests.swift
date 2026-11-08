//
//  HomeKitLivenessTests.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 08.11.26.
//

import Foundation
@testable import HAModels
import Testing

/// Stands in for `StarRemoteCallError`, which carries the adapter error as text.
private struct RemoteCallError: Error {
    let message: String
}

struct HomeKitLivenessTests {

    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    /// The text the adapter sends back when `homed` dropped it (seen in the server log, Nov 2026).
    private let accessDenied = RemoteCallError(message: #"Error Domain=HMErrorDomain Code=80 "Missing entitlement for API." UserInfo={NSLocalizedFailureReason=Handler does not support background access, NSLocalizedDescription=Missing entitlement for API.}"#)

    private func minutes(_ minutes: Double) -> Date {
        start.addingTimeInterval(minutes * 60)
    }

    // MARK: - adapter connection

    @Test("A disconnected adapter is unknown during the grace period, degraded after it")
    func disconnectedAdapter() {
        var liveness = HomeKitLiveness(startedAt: start)

        #expect(liveness.evaluate(isConnected: false, at: minutes(1)) == .unknown(reason: "adapter not connected yet"))
        #expect(liveness.evaluate(isConnected: false, at: minutes(3)) == .degraded(reason: "adapter not connected for 3 min"))
    }

    @Test("A disconnect after a healthy phase gets its own grace period")
    func reconnectGrace() {
        var liveness = HomeKitLiveness(startedAt: start)
        liveness.recordEvent(at: minutes(1))
        #expect(liveness.evaluate(isConnected: true, at: minutes(1)) == .healthy)

        #expect(liveness.evaluate(isConnected: false, at: minutes(30)) == .unknown(reason: "adapter not connected yet"))
        #expect(liveness.evaluate(isConnected: false, at: minutes(33)) == .degraded(reason: "adapter not connected for 3 min"))
    }

    // MARK: - event gap

    @Test("Healthy while events keep arriving within the gap threshold")
    func eventsWithinThreshold() {
        var liveness = HomeKitLiveness(startedAt: start)
        _ = liveness.evaluate(isConnected: true, at: minutes(0))

        liveness.recordEvent(at: minutes(5))
        #expect(liveness.evaluate(isConnected: true, at: minutes(14)) == .healthy)
        liveness.recordEvent(at: minutes(14))
        #expect(liveness.evaluate(isConnected: true, at: minutes(24)) == .healthy)
    }

    @Test("Degraded once no event arrived for longer than the threshold")
    func eventGapDegrades() {
        var liveness = HomeKitLiveness(startedAt: start)
        _ = liveness.evaluate(isConnected: true, at: minutes(0))
        liveness.recordEvent(at: minutes(1))

        #expect(liveness.evaluate(isConnected: true, at: minutes(11)) == .healthy)
        #expect(liveness.evaluate(isConnected: true, at: minutes(12)) == .degraded(reason: "no HomeKit event for 11 min"))
    }

    @Test("A fresh connection gets the full gap threshold before missing events count")
    func freshConnectionGrace() {
        var liveness = HomeKitLiveness(startedAt: start)
        liveness.recordEvent(at: minutes(0))
        _ = liveness.evaluate(isConnected: true, at: minutes(0))
        _ = liveness.evaluate(isConnected: false, at: minutes(1))

        // reconnected after a long outage: the last event is old, but the link is new
        #expect(liveness.evaluate(isConnected: true, at: minutes(60)) == .healthy)
        #expect(liveness.evaluate(isConnected: true, at: minutes(69)) == .healthy)
        #expect(liveness.evaluate(isConnected: true, at: minutes(71)) == .degraded(reason: "no HomeKit event for 11 min"))
    }

    @Test("Recovers as soon as an event arrives again")
    func recoveryAfterGap() {
        var liveness = HomeKitLiveness(startedAt: start)
        _ = liveness.evaluate(isConnected: true, at: minutes(0))
        #expect(liveness.evaluate(isConnected: true, at: minutes(20)) != .healthy)

        liveness.recordEvent(at: minutes(21))
        #expect(liveness.evaluate(isConnected: true, at: minutes(21)) == .healthy)
    }

    // MARK: - Code=80

    @Test("A Code=80 command failure degrades at once, even with recent events")
    func accessDeniedDegrades() {
        var liveness = HomeKitLiveness(startedAt: start)
        _ = liveness.evaluate(isConnected: true, at: minutes(0))
        liveness.recordEvent(at: minutes(1))

        liveness.recordCommandFailure(accessDenied, at: minutes(2))

        #expect(liveness.evaluate(isConnected: true, at: minutes(2)) == .degraded(reason: "HomeKit refuses access (HMErrorDomain Code=80)"))
    }

    @Test("A later event or successful command clears a Code=80 failure", arguments: [true, false])
    func accessDeniedRecovers(byEvent: Bool) {
        var liveness = HomeKitLiveness(startedAt: start)
        _ = liveness.evaluate(isConnected: true, at: minutes(0))
        liveness.recordCommandFailure(accessDenied, at: minutes(1))
        #expect(liveness.evaluate(isConnected: true, at: minutes(1)) != .healthy)

        if byEvent {
            liveness.recordEvent(at: minutes(2))
        } else {
            liveness.recordCommandSuccess(at: minutes(2))
        }

        #expect(liveness.evaluate(isConnected: true, at: minutes(2)) == .healthy)
    }

    @Test("Other command failures leave the health alone")
    func otherFailuresIgnored() {
        var liveness = HomeKitLiveness(startedAt: start)
        _ = liveness.evaluate(isConnected: true, at: minutes(0))

        liveness.recordCommandFailure(RemoteCallError(message: "remote call timed out after 30 seconds"), at: minutes(1))
        liveness.recordCommandFailure(RemoteCallError(message: #"Error Domain=HMErrorDomain Code=74 "Read/Write operation failed.""#), at: minutes(1))
        liveness.recordCommandFailure(RemoteCallError(message: "Error Domain=HMErrorDomain Code=801"), at: minutes(1))

        #expect(liveness.evaluate(isConnected: true, at: minutes(1)) == .healthy)
    }

    @Test("Code=80 is recognised at the end of the text as well")
    func accessDeniedAtEnd() {
        #expect(HomeKitLiveness.isAccessDenied(RemoteCallError(message: "Error Domain=HMErrorDomain Code=80")))
        #expect(!HomeKitLiveness.isAccessDenied(RemoteCallError(message: "Error Domain=HMErrorDomain Code=8")))
    }
}
