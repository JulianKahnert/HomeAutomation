//
//  CustomActorSystem.swift
//  HomeAutomationServer
//
//  Created by Julian Kahnert on 06.02.25.
//

import AsyncAlgorithms
import Distributed
import DistributedCluster
import Foundation
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

public final class CustomActorSystem: Sendable {
    private let log = Logger(label: "ActorSystem")
    private let actorSystem: ClusterSystem
    nonisolated(unsafe) private let _connectionStatus: Any

    /// Stream of connection status changes derived from cluster events.
    /// Shared sequence created once during initialization.
    public var connectionStatus: Any {
        _connectionStatus
    }

    public init(nodeId: NodeIdentity, host: String = "0.0.0.0", port: Int, discovery: DiscoveryMode) async {
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

        // Create shared connection status sequence once using compactMap + share
        let currentNode = actorSystem.cluster.node
        _connectionStatus = actorSystem.cluster.events
            .compactMap { [log] event in
                Self.mapEventToConnectionStatus(
                    event: event,
                    currentNode: currentNode,
                    log: log
                )
            }
            .share()
    }

    /// Maps cluster events to connection status for the local node
    /// - Parameters:
    ///   - event: The cluster event to process
    ///   - currentNode: The current node to filter events for
    ///   - log: Logger instance for event logging
    /// - Returns: Connection status if the event is relevant for the local node, nil otherwise
    private static func mapEventToConnectionStatus(
        event: Cluster.Event,
        currentNode: Cluster.Node,
        log: Logger
    ) -> ConnectionStatus? {
        log.info("Cluster event: \(event)")

        // Extract member from event
        let member: Cluster.Member? = switch event {
        case .membershipChange(let change):
            change.member
        case .reachabilityChange(let change):
            change.member
        case .snapshot(let members):
            members.first(where: { $0.node == currentNode })
        case .leadershipChange:
            nil
        default:
            nil
        }

        // Only process events for our own node
        guard let member, member.node == currentNode else {
            return nil
        }

        // Map member status to connection status
        return Self.mapMemberStatusToConnectionStatus(member: member, log: log)
    }

    /// Maps cluster member status to connection status
    /// - Parameters:
    ///   - member: The cluster member
    ///   - log: Logger instance for status logging
    /// - Returns: Connection status if the member status is relevant, nil otherwise
    private static func mapMemberStatusToConnectionStatus(
        member: Cluster.Member,
        log: Logger
    ) -> ConnectionStatus? {
        switch member.status {
        case .joining:
            log.info("Member joined: \(member.node)")
            return .joining

        case .up:
            log.info("Member is up: \(member.node)")
            return .up

        case .removed:
            log.warning("Member removed: \(member.node)")
            return .error

        case .leaving:
            log.info("Member leaving: \(member.node)")
            return nil

        default:
            log.warning("Unknown membership status: \(member.status)")
            return nil
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
