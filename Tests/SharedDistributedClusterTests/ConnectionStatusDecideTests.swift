//
//  ConnectionStatusDecideTests.swift
//  HomeAutomationKit
//
//  Unit tests for the pure peer-status decision function used to derive `ConnectionStatus`.
//  Mirrors the verdict matrix from the "Server Down" debugging runbook.
//

import DistributedCluster
@testable import SharedDistributedCluster
import Testing

struct ConnectionStatusDecideTests {
    typealias Peer = (status: Cluster.MemberStatus, reachability: Cluster.MemberReachability)

    @Test("No peer yet → joining")
    func noPeer() {
        #expect(CustomActorSystem.decide(peers: []) == .joining)
    }

    @Test("Reachable up peer → up")
    func reachableUp() {
        let peers: [Peer] = [(status: .up, reachability: .reachable)]
        #expect(CustomActorSystem.decide(peers: peers) == .up)
    }

    @Test("Reachable joining peer → joining (mid-handshake)")
    func reachableJoining() {
        let peers: [Peer] = [(status: .joining, reachability: .reachable)]
        #expect(CustomActorSystem.decide(peers: peers) == .joining)
    }

    @Test("Up but unreachable peer → error")
    func upUnreachable() {
        let peers: [Peer] = [(status: .up, reachability: .unreachable)]
        #expect(CustomActorSystem.decide(peers: peers) == .error)
    }

    @Test("Down + reachable peer → error")
    func downReachable() {
        let peers: [Peer] = [(status: .down, reachability: .reachable)]
        #expect(CustomActorSystem.decide(peers: peers) == .error)
    }

    @Test("Down + unreachable peer → error")
    func downUnreachable() {
        let peers: [Peer] = [(status: .down, reachability: .unreachable)]
        #expect(CustomActorSystem.decide(peers: peers) == .error)
    }

    @Test("Removed peer → error")
    func removedPeer() {
        let peers: [Peer] = [(status: .removed, reachability: .reachable)]
        #expect(CustomActorSystem.decide(peers: peers) == .error)
    }

    // The literal incident: a stale dead node lingers (.down/.unreachable) while a fresh instance
    // re-joins on the same endpoint (.joining). We must report .joining (recovering), not .error.
    @Test("Replacement: stale down peer + new joining peer → joining")
    func replacementInProgress() {
        let peers: [Peer] = [
            (status: .down, reachability: .unreachable),
            (status: .joining, reachability: .reachable)
        ]
        #expect(CustomActorSystem.decide(peers: peers) == .joining)
    }

    @Test("A healthy peer wins over a lingering stale peer → up")
    func healthyWinsOverStale() {
        let peers: [Peer] = [
            (status: .up, reachability: .reachable),
            (status: .down, reachability: .unreachable)
        ]
        #expect(CustomActorSystem.decide(peers: peers) == .up)
    }
}
