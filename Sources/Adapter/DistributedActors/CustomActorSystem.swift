//
//  CustomActorSystem.swift
//  HomeAutomationServer
//
//  Created by Julian Kahnert on 06.02.25.
//

import Distributed
import DistributedCluster
import Logging
import ServiceDiscovery

typealias DefaultDistributedActorSystem = ClusterSystem

public struct NodeIdentity: Sendable {
    let id: String
}

public final class CustomActorSystem: Sendable {
    private let log = Logger(label: "ActorSystem")
    private let actorSystem: ClusterSystem

    public init(nodeId: NodeIdentity, host: String = "0.0.0.0", port: Int) async {
        let allNodes = Set<Cluster.Endpoint>([
            .init(host: "0.0.0.0", port: 7777),
            .init(host: "0.0.0.0", port: 8888)
        ])

        // Remove "self" to prevent hangs in initial connection between adapter and server
        let nodes = allNodes.filter { $0.port != port }

        // setup cluster
        var settings = ClusterSystemSettings(name: nodeId.id, host: host, port: port)
        settings.discovery = ServiceDiscoverySettings(static: nodes)
        settings.logging.logLevel = .warning
        actorSystem = await ClusterSystem(nodeId.id, settings: settings)

        // start logging
        Task {
            for await event in self.actorSystem.cluster.events {
                log.info("received event: \(event)")
            }
        }
    }

    public var endpointDescription: String {
        actorSystem.cluster.endpoint.description
    }

    public func makeLocalActor<Guest>(actorId: DistributedReception.Key<Guest>, _ factory: (ClusterSystem) -> Guest) -> Guest
        where Guest: DistributedActor, Guest.ActorSystem == ClusterSystem {
        return factory(actorSystem)
    }

    @discardableResult
    public func checkIn<Guest>(actorId: DistributedReception.Key<Guest>, _ actor: Guest) async -> Guest where Guest: DistributedActor, Guest.ActorSystem == ClusterSystem {
        await actorSystem.receptionist.checkIn(actor, with: actorId)
        return actor
    }

    public func lookup<Guest>(_ key: DistributedReception.Key<Guest>) async -> Guest? where Guest: DistributedActor, Guest.ActorSystem == ClusterSystem {
        return await actorSystem.receptionist.lookup(key).first
    }

    public func listing<Guest>(of key: DistributedReception.Key<Guest>) async -> DistributedReception.GuestListing<Guest>
    where Guest: DistributedActor, Guest.ActorSystem == ClusterSystem {
        return await actorSystem.receptionist.listing(of: key)
    }

    public func joined(within duration: Duration) async throws {
        try await actorSystem.cluster.joined(within: duration)
    }

    public func waitForThisNode(is clusterState: Cluster.MemberStatus, within duration: Duration) async throws {
        try await actorSystem.cluster.waitFor(actorSystem.cluster.node, clusterState, within: duration)
    }

    public func join(host: String, port: Int) {
        actorSystem.cluster.join(endpoint: .init(host: host, port: port))
    }
}
