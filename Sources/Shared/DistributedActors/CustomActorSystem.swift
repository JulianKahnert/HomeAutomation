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

/// Connection status of the distributed actor system
public enum ConnectionStatus: Sendable {
    /// Successfully connected
    case up
    /// Attempting to connect
    case joining
    /// Connection failed/lost
    case error
}

/// System role that determines both node identity and discovery behavior
public enum SystemRole: Sendable {
    /// Server role: accepts connections from adapters
    case server
    /// HomeKit Adapter role: connects to a specific server
    case homeKitAdapter(serverAddress: CustomActorSystem.Address)

    /// The node identity for this system role
    var name: String {
        switch self {
        case .server:
            return "server"
        case .homeKitAdapter:
            return "homeKitAdapter"
        }
    }

    var host: String {
        "0.0.0.0"
    }

    var port: Int {
        switch self {
        case .server:
            return 8888
        case .homeKitAdapter:
            return 7777
        }
    }
}

public actor CustomActorSystem {
    private static let log = Logger(label: "CustomActorSystem")
    private let systemRole: SystemRole
    private let actorSystem: ClusterSystem
    private var reconnectionTask: Task<Void, Error>?
    private var currentConnectionStatus: ConnectionStatus?
    private var _connectionStatus: (any AsyncSequence<ConnectionStatus, Never> & Sendable)!

    /// Stream of connection status changes derived from cluster events.
    /// Shared sequence created once during initialization.
    public var connectionStatus: any AsyncSequence<ConnectionStatus, Never> & Sendable {
        _connectionStatus
    }

    /// Returns the most recent connection status, or nil if no event has been received yet.
    public var latestConnectionStatus: ConnectionStatus? {
        currentConnectionStatus
    }

    /// - Parameters:
    ///   - role: The system role (server or adapter)
    ///   - onDown: Optional closure called when the connection is lost and does not recover within 60s.
    ///     The built-in `onDownAction: .gracefulShutdown` only shuts down the actor system, not the
    ///     hosting process. This closure allows the caller to terminate the entire process (e.g. `exit(1)`).
    public init(role: SystemRole, onDown: (@Sendable () -> Void)? = nil) async {
        self.systemRole = role

        // Setup cluster settings
        var settings = ClusterSystemSettings(name: role.name, host: role.host, port: role.port)

        // Configure discovery based on role
        switch role {
        case .server:
            // Server: No discovery, only accept connections
            settings.discovery = nil

        case .homeKitAdapter(serverAddress: let address):
            // Adapter: Discover specific server
            let endpoint = Cluster.Endpoint(host: address.host, port: address.port)
            settings.discovery = ServiceDiscoverySettings(static: [endpoint])
        }

        settings.remoteCall.defaultTimeout = .seconds(15)
        settings.logging.logLevel = .warning

        // We handle down events ourselves via the onDown closure instead of using the
        // built-in .gracefulShutdown, which only shuts down the actor system but not
        // the hosting process (Vapor server). We need a full process exit so Docker
        // can restart the container.
        if case .server = role {
            settings.onDownAction = .none
        }

        actorSystem = await ClusterSystem(role.name, settings: settings)

        // Create shared connection status sequence once using compactMap + share
        _connectionStatus = actorSystem.cluster.events
            .compactMap { event in
                Self.mapEventToConnectionStatus(event: event)
            }
            .share()

        switch role {
        case .homeKitAdapter:
            tryReconnectIfNeededInBackground()
        default:
            break
        }

        Task {
            for await status in connectionStatus {
                currentConnectionStatus = status

                if status == .error, let onDown {
                    Self.log.warning("Connection lost. Waiting 60s for reconnection...")
                    try? await Task.sleep(for: .seconds(60))

                    guard currentConnectionStatus != .up else {
                        Self.log.info("Reconnected during grace period.")
                        continue
                    }

                    Self.log.critical("Still disconnected after grace period. Calling onDown handler.")
                    onDown()
                }
            }
        }
    }

    /// Maps cluster events to connection status for the local node
    /// - Parameters:
    ///   - event: The cluster event to process
    ///   - log: Logger instance for event logging
    /// - Returns: Connection status if the event is relevant for the local node, nil otherwise
    private static func mapEventToConnectionStatus(event: Cluster.Event) -> ConnectionStatus? {
        log.info("Cluster event: \(event)")

        guard case Cluster.Event.membershipChange(let change) = event else { return nil }
        switch change.member.status {
        case .joining:
            return .joining
        case .up:
            return .up
        case .leaving:
            return nil
        case .down, .removed:
            return .error
        default:
            return nil
        }
    }

    nonisolated public var endpointDescription: String {
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

    private func tryReconnectIfNeededInBackground() {
        reconnectionTask?.cancel()
        reconnectionTask = Task { [weak actorSystem] in
            while true {
                guard let actorSystem else {
                    assertionFailure()
                    return
                }

                do {
                    Self.log.debug("wait for node")
                    try await actorSystem.cluster.waitFor(actorSystem.cluster.node, .up, within: .seconds(10))

                    Self.log.info("get status: \(String(describing: currentConnectionStatus))")
                    if currentConnectionStatus != .up,
                       case .homeKitAdapter(serverAddress: let address) = systemRole {
                        Self.log.warning("the node (\(systemRole) is up but there is no connection - joining again for 30s")
//                        try await actorSystem.joined(host: address.host, port: address.port, within: .seconds(30))
                        try await actorSystem.cluster.joined(endpoint: .init(host: address.host, port: address.port), within: .seconds(30))
                    }
                    Self.log.info("continue")
                } catch {
                    Self.log.error("Failed to initialize the actor system: \(error)")
                }

                Self.log.debug("waiting 20s")
                try await Task.sleep(for: .seconds(20))
                Self.log.debug("waiting 20s - finished")
            }
        }
    }
}
