//
//  WatchdogTests.swift
//  HomeAutomationKit
//
//  Unit tests for the stuck-non-up watchdog (#190 Finding 1). All escalation rules live in the
//  pure `watchdogDecision` function, so the complete ladder — boot → wedge → evict → re-arm →
//  self-exit — is testable as timeline scenarios without a running cluster.
//

import DistributedCluster
import Foundation
@testable import SharedDistributedCluster
import Testing

struct WatchdogTests {

    /// A fixed timeline origin; scenarios advance from here.
    private let boot = Date(timeIntervalSinceReferenceDate: 0)

    private func decision(
        after seconds: TimeInterval,
        connectionStatus: ConnectionStatus? = .joining,
        notUpSince: TimeInterval? = nil,
        lastEvictionAt: TimeInterval? = nil,
        everConnected: Bool = false,
        hasPeers: Bool = true
    ) -> CustomActorSystem.WatchdogDecision {
        CustomActorSystem.watchdogDecision(
            connectionStatus: connectionStatus,
            now: boot.addingTimeInterval(seconds),
            notUpSince: notUpSince.map(boot.addingTimeInterval),
            bootDate: boot,
            lastEvictionAt: lastEvictionAt.map(boot.addingTimeInterval),
            everConnected: everConnected,
            hasPeers: hasPeers
        )
    }

    // MARK: - No-op conditions

    @Test("While .up the watchdog does nothing")
    func upIsNoop() {
        #expect(decision(after: 100_000, connectionStatus: .up) == .noop)
    }

    @Test("Without a visible peer the watchdog does nothing — an absent adapter must never restart-loop the server")
    func noPeersIsNoop() {
        #expect(decision(after: 100_000, hasPeers: false) == .noop)
        #expect(decision(after: 100_000, everConnected: true, hasPeers: false) == .noop)
    }

    // MARK: - Eviction phase

    @Test("Cold-boot wedge timeline: quiet before the eviction threshold, evicting at it")
    func coldBootWedgeEvicts() {
        let threshold = CustomActorSystem.watchdogEvictionAfter
        // notUpSince == nil (no event yet): duration counts from bootDate.
        #expect(decision(after: threshold - 1) == .noop)
        #expect(decision(after: threshold) == .init(shouldEvictPeers: true, shouldSelfExit: false))
    }

    @Test("Eviction re-arms only after another full window — a rejoining fresh peer gets time to come up")
    func evictionReArmsAfterFullWindow() {
        let threshold = CustomActorSystem.watchdogEvictionAfter
        // Evicted once at `threshold`; still wedged afterwards.
        #expect(decision(after: threshold + 10, lastEvictionAt: threshold).shouldEvictPeers == false)
        #expect(decision(after: threshold * 2, lastEvictionAt: threshold).shouldEvictPeers == true)
    }

    @Test("A connection drop mid-run counts from the drop, not from boot")
    func stuckDurationCountsFromDrop() {
        let threshold = CustomActorSystem.watchdogEvictionAfter
        let dropAt: TimeInterval = 50_000
        // Long-running process (everConnected), connection dropped at `dropAt`.
        #expect(decision(after: dropAt + threshold - 1, notUpSince: dropAt, everConnected: true) == .noop)
        #expect(decision(after: dropAt + threshold, notUpSince: dropAt, everConnected: true).shouldEvictPeers == true)
    }

    // MARK: - Self-exit backstop

    @Test("Warm wedge (was .up in this process): self-exit after the warm threshold")
    func warmWedgeSelfExits() {
        let warm = CustomActorSystem.watchdogSelfExitAfterWarm
        #expect(decision(after: warm - 1, notUpSince: 0, everConnected: true).shouldSelfExit == false)
        #expect(decision(after: warm, notUpSince: 0, everConnected: true).shouldSelfExit == true)
    }

    @Test("Never-up boot: self-exit only after the (longer) cold threshold — no tight boot loops")
    func coldWedgeSelfExitsLater() {
        let warm = CustomActorSystem.watchdogSelfExitAfterWarm
        let cold = CustomActorSystem.watchdogSelfExitAfterCold
        #expect(cold > warm)
        #expect(decision(after: warm).shouldSelfExit == false)
        #expect(decision(after: cold - 1).shouldSelfExit == false)
        #expect(decision(after: cold).shouldSelfExit == true)
    }

    @Test("The verified wedge scenario end-to-end: evict first, self-exit as backstop")
    func wedgeEscalationLadder() {
        // Server restarts into a wedge: stale reachable .joining adapter member visible,
        // never .up in this process.
        let evictAt = CustomActorSystem.watchdogEvictionAfter
        let exitAt = CustomActorSystem.watchdogSelfExitAfterCold

        // Phase 1: eviction fires long before the self-exit backstop.
        let phase1 = decision(after: evictAt)
        #expect(phase1 == .init(shouldEvictPeers: true, shouldSelfExit: false))

        // Phase 2: if eviction did not heal the cluster, the backstop eventually fires.
        let phase2 = decision(after: exitAt, lastEvictionAt: exitAt - 10)
        #expect(phase2.shouldSelfExit == true)
    }

    // MARK: - Eviction candidates

    @Test("The wedge member — reachable and stuck .joining — IS an eviction candidate")
    func reachableJoiningIsCandidate() {
        // This is the exact member the 2026-06-19 wedge left behind: a dead old UID that stays
        // REACHABLE (the new process on the same host:port answers its SWIM probes) and .joining —
        // which is why any reachability-based downing can never catch it.
        #expect(CustomActorSystem.isWatchdogEvictionCandidate(status: .joining, isSelf: false))
    }

    @Test(".up and .leaving peers are candidates too (stuck below convergence)")
    func upAndLeavingAreCandidates() {
        #expect(CustomActorSystem.isWatchdogEvictionCandidate(status: .up, isSelf: false))
        #expect(CustomActorSystem.isWatchdogEvictionCandidate(status: .leaving, isSelf: false))
    }

    @Test("Already-down/removed members and the local node are never evicted")
    func downedAndSelfAreNotCandidates() {
        #expect(CustomActorSystem.isWatchdogEvictionCandidate(status: .down, isSelf: false) == false)
        #expect(CustomActorSystem.isWatchdogEvictionCandidate(status: .removed, isSelf: false) == false)
        #expect(CustomActorSystem.isWatchdogEvictionCandidate(status: .joining, isSelf: true) == false)
    }

    // MARK: - Adapter grace period

    @Test("Grace period is short after a previous .up, longer — but armed — on a never-up boot")
    func gracePeriodScales() {
        #expect(CustomActorSystem.gracePeriod(everConnected: true) == CustomActorSystem.graceAfterConnectionLoss)
        #expect(CustomActorSystem.gracePeriod(everConnected: false) == CustomActorSystem.graceOnNeverUpBoot)
        #expect(CustomActorSystem.graceOnNeverUpBoot > CustomActorSystem.graceAfterConnectionLoss)
    }
}

/// Tests for the reconnect-transition helper driving the adapter's full-state resync
/// (#190 Findings 6/7).
struct ReconnectTransitionTests {

    @Test("First .up (no prior status) is a reconnect — covers the boot-time push race")
    func firstUpIsReconnect() {
        #expect(ConnectionStatus.up.isReconnect(from: nil))
    }

    @Test("Recovering from joining/error is a reconnect")
    func recoveryIsReconnect() {
        #expect(ConnectionStatus.up.isReconnect(from: .joining))
        #expect(ConnectionStatus.up.isReconnect(from: .error))
    }

    @Test("Staying .up or leaving .up is not a reconnect")
    func nonTransitionsAreNot() {
        #expect(ConnectionStatus.up.isReconnect(from: .up) == false)
        #expect(ConnectionStatus.joining.isReconnect(from: .up) == false)
        #expect(ConnectionStatus.error.isReconnect(from: .joining) == false)
    }
}
