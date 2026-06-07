//
//  ClusterLeadershipTests.swift
//  HomeAutomationKit
//
//  In-process cluster tests validating the leader-deadlock fix:
//  - only the server may become leader (server: minNumberOfMembers 1, adapter: .none)
//  - the server self-heals: promotes a (re)joining adapter to .up and downs a dead adapter.
//
//  These spin up real ClusterSystems on localhost test ports. They are timing-sensitive, so the
//  suite is serialized and uses generous timeouts.
//

import DistributedCluster
@testable import SharedDistributedCluster
import Testing

@Suite(.serialized)
struct ClusterLeadershipTests {

    private static func makeServer(port: Int) async -> ClusterSystem {
        let settings = CustomActorSystem.makeClusterSettings(role: .server, host: "127.0.0.1", port: port)
        return await ClusterSystem("server", settings: settings)
    }

    private static func makeAdapter(port: Int, serverPort: Int) async -> ClusterSystem {
        let serverAddress = CustomActorSystem.Address(host: "127.0.0.1", port: serverPort)
        let settings = CustomActorSystem.makeClusterSettings(
            role: .homeKitAdapter(serverAddress: serverAddress),
            host: "127.0.0.1",
            port: port
        )
        return await ClusterSystem("homeKitAdapter", settings: settings)
    }

    @Test("Server alone self-elects as leader (minNumberOfMembers: 1)")
    func serverAloneBecomesLeader() async throws {
        let server = await Self.makeServer(port: 19_001)
        defer { _ = try? server.shutdown() }

        try await server.cluster.waitFor(server.cluster.node, .up, within: .seconds(30))

        let membership = await server.cluster.membershipSnapshot
        #expect(membership.leader?.node == server.cluster.node)
    }

    @Test("Adapter alone never becomes leader (autoLeaderElection: .none)")
    func adapterAloneNeverBecomesLeader() async throws {
        // Points at a server that isn't running — the adapter must still never elect itself.
        let adapter = await Self.makeAdapter(port: 19_003, serverPort: 19_002)
        defer { _ = try? adapter.shutdown() }

        try await Task.sleep(for: .seconds(5))

        let membership = await adapter.cluster.membershipSnapshot
        #expect(membership.leader == nil)
        #expect(membership.isLeader(adapter.cluster.node) == false)
    }

    @Test("Server promotes a joining adapter to .up, then downs it when it dies")
    func serverPromotesThenDownsAdapter() async throws {
        let serverPort = 19_004
        let adapterPort = 19_005

        let server = await Self.makeServer(port: serverPort)
        defer { _ = try? server.shutdown() }
        let adapter = await Self.makeAdapter(port: adapterPort, serverPort: serverPort)
        let adapterNode = adapter.cluster.node

        adapter.cluster.join(endpoint: server.cluster.endpoint)

        // The server (leader) promotes itself and the adapter to .up.
        try await server.cluster.waitFor(server.cluster.node, .up, within: .seconds(30))
        try await server.cluster.waitFor(adapterNode, .up, within: .seconds(30))

        var membership = await server.cluster.membershipSnapshot
        #expect(membership.leader?.node == server.cluster.node)
        #expect(membership.isLeader(adapterNode) == false)

        // Kill the adapter; the server (leader, downUnreachableMembersAfter: 10s) evicts it.
        _ = try? adapter.shutdown()

        try await server.cluster.waitFor(adapterNode, atLeast: .down, within: .seconds(60))

        membership = await server.cluster.membershipSnapshot
        #expect(membership.member(server.cluster.node)?.status == .up)
        #expect(membership.leader?.node == server.cluster.node)
    }
}
