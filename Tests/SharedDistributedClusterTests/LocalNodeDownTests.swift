//
//  LocalNodeDownTests.swift
//  HomeAutomationKit
//
//  Unit tests for local-node-down detection. When the leader evicts the local node (e.g. after a
//  partition longer than `downUnreachableMembersAfter`), the node is terminal for its current UID and
//  must restart — peer-based status alone would miss this (it filters out self).
//

import DistributedCluster
@testable import SharedDistributedCluster
import Testing

struct LocalNodeDownTests {
    @Test(".down is terminal")
    func down() {
        #expect(CustomActorSystem.isLocalNodeDown(selfStatus: .down) == true)
    }

    @Test(".removed is terminal")
    func removed() {
        #expect(CustomActorSystem.isLocalNodeDown(selfStatus: .removed) == true)
    }

    @Test(".up is healthy")
    func up() {
        #expect(CustomActorSystem.isLocalNodeDown(selfStatus: .up) == false)
    }

    @Test(".joining is not down")
    func joining() {
        #expect(CustomActorSystem.isLocalNodeDown(selfStatus: .joining) == false)
    }

    // .leaving is a graceful transition (never self-initiated here) and must not trigger a restart.
    @Test(".leaving is not treated as down")
    func leaving() {
        #expect(CustomActorSystem.isLocalNodeDown(selfStatus: .leaving) == false)
    }

    @Test("nil (self not yet in membership) is not down")
    func notInMembership() {
        #expect(CustomActorSystem.isLocalNodeDown(selfStatus: nil) == false)
    }
}
