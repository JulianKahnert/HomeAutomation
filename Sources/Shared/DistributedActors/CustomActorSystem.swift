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

/// Connection status of the distributed actor system
public enum ConnectionStatus: Sendable {
    /// Successfully connected
    case up
    /// Attempting to connect
    case joining
    /// Connection failed/lost
    case error
}

/// Discovery mode for cluster initialization
public enum DiscoveryMode: Sendable {
    /// Server mode: no discovery, only accept connections
    case none
    /// Adapter mode: connect to specific server
    case staticEndpoint(CustomActorSystem.Address)
}

/// Actor to manage connection status in a thread-safe way
actor ConnectionStatusActor {
    private(set) var status: ConnectionStatus = .joining

    func updateStatus(_ newStatus: ConnectionStatus) {
        status = newStatus
    }
}

public final class CustomActorSystem: Sendable {
    private let log = Logger(label: "ActorSystem")
    private let actorSystem: ClusterSystem
    private let statusActor: ConnectionStatusActor

    /// Current connection status (observable for UI)
    // TODO: this should be a stream
    public var connectionStatus: ConnectionStatus {
        get async {
            await statusActor.status
        }
    }

    public init(nodeId: NodeIdentity, host: String = "0.0.0.0", port: Int, discovery: DiscoveryMode) async {
        // Initialize connection status actor
        statusActor = ConnectionStatusActor()

        // Setup cluster settings
        var settings = ClusterSystemSettings(name: nodeId.id, host: host, port: port)

        // Configure discovery based on mode
        switch discovery {
        case .none:
            // Server: No discovery, only accept connections
            settings.discovery = nil

        case .staticEndpoint(let address):
            // Adapter: Discover specific server
            let endpoint = Cluster.Endpoint(host: address.host, port: address.port)
            settings.discovery = ServiceDiscoverySettings(static: [endpoint])
        }

        settings.logging.logLevel = .warning
        actorSystem = await ClusterSystem(nodeId.id, settings: settings)

        // Start monitoring cluster events for connection status
        Task {
            await self.monitorClusterEvents()
        }
    }

    /// Monitor cluster events and update connection status
    private func monitorClusterEvents() async {
        for await event in actorSystem.cluster.events {
            log.info("Cluster event: \(event)")
            await updateConnectionState(event)
        }
    }

    /// Update connection state based on cluster events
    private func updateConnectionState(_ event: Cluster.Event) async {
        switch event {
        case .membershipChange(let change):
            await handleChange(of: change.member)
        case .reachabilityChange(let change):
            await handleChange(of: change.member)
        case .leadershipChange:
            // Leader changes don't affect our connection status
            break
        case .snapshot(let members):
            // Snapshot events are informational only
            guard let member = members.first(where: { $0.node == actorSystem.cluster.node }) else { break }
            await handleChange(of: member)
        default:
            log.warning("Unknown cluster event type: \(event)")
        }
    }

    /// Handle cluster membership changes
    private func handleChange(of member: Cluster.Member) async {
        guard actorSystem.cluster.node == member.node else { return }

        switch member.status {
        case .joining:
            log.info("Member joined: \(member.node)")
            await statusActor.updateStatus(.joining)

        case .up:
            log.info("Member is up: \(member.node)")
            // Update to 'up' status when we or another member is fully up
            await statusActor.updateStatus(.up)

        case .leaving:
            log.info("Member leaving: \(member.node)")

        case .removed:
            log.warning("Member removed: \(member.node)")
            // If we're tracking a specific server and it's removed, mark as error
            await statusActor.updateStatus(.error)

        default:
            log.warning("Unknown membership change: \(member)")
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

    public func listing<Guest>(of key: DistributedReception.Key<Guest>) async -> DistributedReception.GuestListing<Guest> where Guest: DistributedActor, Guest.ActorSystem == ClusterSystem {
        return await actorSystem.receptionist.listing(of: key)
    }

    public func waitForThisNode(is clusterState: Cluster.MemberStatus, within duration: Duration) async throws {
        try await actorSystem.cluster.waitFor(actorSystem.cluster.node, clusterState, within: duration)
    }

    public func join(host: String, port: Int) {
        actorSystem.cluster.join(endpoint: .init(host: host, port: port))
    }
}
