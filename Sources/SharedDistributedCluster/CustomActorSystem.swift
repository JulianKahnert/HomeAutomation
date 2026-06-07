//
//  CustomActorSystem.swift
//  HomeAutomationServer
//
//  Created by Julian Kahnert on 06.02.25.
//

import Distributed
import DistributedCluster
import Foundation
import Logging
import ServiceDiscovery

typealias DefaultDistributedActorSystem = ClusterSystem

/// Connection status of the distributed actor system, as seen from the local node towards its peer.
public enum ConnectionStatus: Sendable, Equatable {
    /// A reachable peer is `.up` — the cluster is healthy.
    case up
    /// No peer yet, or a reachable peer is still handshaking / coming up.
    case joining
    /// A known peer is down / removed / unreachable.
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
    private let onDown: (@Sendable () -> Void)?

    private var reconnectionTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var graceTask: Task<Void, Never>?

    /// The most recent connection status, or nil if no cluster event has been processed yet.
    private var currentConnectionStatus: ConnectionStatus?
    /// Whether a reachable peer ever reached `.up`. Gates the `onDown` recovery so we don't
    /// terminate during the initial boot (before the peer connects for the first time).
    private var everConnected = false
    /// Live subscribers to `connectionStatus`. Each gets the current value first, then live updates.
    private var subscribers: [UUID: AsyncStream<ConnectionStatus>.Continuation] = [:]

    /// Returns the most recent connection status, or nil if no event has been received yet.
    public var latestConnectionStatus: ConnectionStatus? {
        currentConnectionStatus
    }

    /// A fresh stream of connection status changes. The stream is seeded with the *current* value
    /// (so late subscribers never miss the latest state — unlike a plain broadcast), followed by
    /// live updates.
    public var connectionStatus: AsyncStream<ConnectionStatus> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: ConnectionStatus.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        if let current = currentConnectionStatus {
            continuation.yield(current)
        }
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id) }
        }
        return stream
    }

    /// - Parameters:
    ///   - role: The system role (server or adapter)
    ///   - onDown: Optional closure called when the connection to the peer is lost and does not
    ///     recover within a grace period (and the peer had connected at least once before).
    ///     Used by the **adapter** to `exit(1)` so launchctl restarts it with a fresh node UID.
    ///     The **server** passes `nil` — it never terminates; it stays alive and heals as the
    ///     cluster leader.
    public init(role: SystemRole, onDown: (@Sendable () -> Void)? = nil) async {
        self.systemRole = role
        self.onDown = onDown

        let settings = Self.makeClusterSettings(role: role)
        actorSystem = await ClusterSystem(role.name, settings: settings)

        // Derive connection status from cluster events (membership + reachability).
        startStatusTask()

        // Only the adapter actively (re)connects to the server.
        if case .homeKitAdapter = role {
            tryReconnectIfNeededInBackground()
        }
    }

    // MARK: - Cluster settings

    /// Builds the cluster settings for a given role. Pure & deterministic so it can be unit-tested
    /// (leader selection / downing behavior).
    ///
    /// Key invariants:
    /// - **Only the server may ever become leader.** The server self-elects with a single reachable
    ///   member (`minNumberOfMembers: 1`), so it can promote a (re)joining adapter to `.up` and down
    ///   dead members — letting the cluster self-heal. The adapter uses `.none` and therefore never
    ///   becomes leader, which prevents a mutual-down split-brain.
    /// - Downing is left enabled (it only fires while a leader exists, i.e. on the server) but with a
    ///   tolerant timeout so brief blips don't evict the peer.
    /// - `onDownAction = .none` on both: we never let the library silently shut the system down;
    ///   recovery is handled explicitly (server stays alive as leader, adapter reconnects/restarts).
    /// - Parameters:
    ///   - host/port: optional bind overrides (used by tests to avoid the fixed production ports).
    public static func makeClusterSettings(role: SystemRole, host: String? = nil, port: Int? = nil) -> ClusterSystemSettings {
        var settings = ClusterSystemSettings(name: role.name, host: host ?? role.host, port: port ?? role.port)

        switch role {
        case .server:
            settings.discovery = nil
            settings.autoLeaderElection = .lowestReachable(minNumberOfMembers: 1)

            var downing = TimeoutBasedDowningStrategySettings.default
            downing.downUnreachableMembersAfter = .seconds(10)
            settings.downingStrategy = .timeout(downing)

        case .homeKitAdapter(serverAddress: let address):
            let endpoint = Cluster.Endpoint(host: address.host, port: address.port)
            settings.discovery = ServiceDiscoverySettings(static: [endpoint])
            settings.autoLeaderElection = .none
        }

        settings.onDownAction = .none
        settings.remoteCall.defaultTimeout = .seconds(15)
        settings.logging.logLevel = .warning
        return settings
    }

    // MARK: - Connection status derivation

    /// Pure decision function: maps the peer members' (status, reachability) to a connection status.
    /// Kept free of `Cluster.Node`/`Cluster.Membership` construction so it is trivially unit-testable.
    public static func decide(peers: [(status: Cluster.MemberStatus, reachability: Cluster.MemberReachability)]) -> ConnectionStatus {
        if peers.isEmpty {
            return .joining
        }
        if peers.contains(where: { $0.status == .up && $0.reachability == .reachable }) {
            return .up
        }
        if peers.contains(where: { $0.reachability == .reachable && $0.status < .up }) {
            return .joining
        }
        return .error
    }

    /// Derives the connection status for `selfNode` from a full membership, considering only peers
    /// (members other than self) and their reachability.
    public static func connectionStatus(for membership: Cluster.Membership, selfNode: Cluster.Node) -> ConnectionStatus {
        let peers = membership.members(atLeast: .joining)
            .filter { $0.node != selfNode }
            .map { (status: $0.status, reachability: $0.reachability) }
        return decide(peers: peers)
    }

    private func startStatusTask() {
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            guard let self else { return }
            let events = self.actorSystem.cluster.events
            let selfNode = self.actorSystem.cluster.node
            var membership = Cluster.Membership.empty
            for await event in events {
                Self.log.debug("Cluster event: \(event)")
                _ = try? membership.apply(event: event)
                let status = Self.connectionStatus(for: membership, selfNode: selfNode)
                await self.handleStatus(status)
            }
        }
    }

    private func handleStatus(_ status: ConnectionStatus) {
        let changed = status != currentConnectionStatus
        currentConnectionStatus = status
        if changed {
            Self.log.info("Connection status: \(status)")
            for continuation in subscribers.values {
                continuation.yield(status)
            }
        }

        // Recovery is opt-in via `onDown` (adapter only). The server passes nil and never terminates.
        guard let onDown else { return }

        if status == .up {
            everConnected = true
            graceTask?.cancel()
            graceTask = nil
            return
        }

        // Peer not up: start a single grace timer, but only after we had connected at least once,
        // and only if one isn't already pending.
        guard everConnected, graceTask == nil else { return }
        graceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard let self else { return }
            guard await self.currentConnectionStatus != .up else {
                Self.log.info("Reconnected during grace period.")
                return
            }
            Self.log.critical("Still disconnected after grace period. Calling onDown handler.")
            onDown()
        }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
    }

    // MARK: - Reconnection (adapter)

    private func tryReconnectIfNeededInBackground() {
        reconnectionTask?.cancel()
        reconnectionTask = Task { [weak self] in
            guard let self else { return }
            guard case .homeKitAdapter(serverAddress: let address) = self.systemRole else { return }
            let serverEndpoint = Cluster.Endpoint(host: address.host, port: address.port)

            while !Task.isCancelled {
                do {
                    let snapshot = await self.actorSystem.cluster.membershipSnapshot
                    let selfNode = self.actorSystem.cluster.node
                    let status = Self.connectionStatus(for: snapshot, selfNode: selfNode)

                    if status != .up {
                        // Evict any stale server node lingering on the target endpoint (a previous
                        // server instance with a now-dead UID). Manual `down(member:)` is leader-
                        // independent, and targeting the specific *member* avoids downing the fresh
                        // server that may already be (re)joining on the same host:port.
                        let staleServerMembers = snapshot.members(atLeast: .joining).filter { member in
                            member.node != selfNode
                                && member.node.endpoint.host == serverEndpoint.host
                                && member.node.endpoint.port == serverEndpoint.port
                                && (member.reachability == .unreachable || member.status >= .down)
                        }
                        for member in staleServerMembers {
                            Self.log.warning("Downing stale server member before rejoin: \(member)")
                            self.actorSystem.cluster.down(member: member)
                        }

                        Self.log.info("Peer not up (\(status)) — (re)joining \(serverEndpoint)")
                        _ = try await self.actorSystem.cluster.joined(endpoint: serverEndpoint, within: .seconds(30))
                    }
                } catch {
                    Self.log.error("Reconnect attempt failed: \(error)")
                }

                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    // MARK: - Lifecycle

    /// Cancels all background tasks and shuts down the underlying cluster system. Must be called when
    /// the owner (e.g. the SwiftUI adapter app on server-address change) discards this instance, to
    /// avoid leaking a cluster node, its tasks and its bound port.
    public func shutdown() async {
        reconnectionTask?.cancel()
        statusTask?.cancel()
        graceTask?.cancel()
        reconnectionTask = nil
        statusTask = nil
        graceTask = nil
        for continuation in subscribers.values {
            continuation.finish()
        }
        subscribers.removeAll()
        _ = try? actorSystem.shutdown()
    }

    // MARK: - Distributed actor helpers

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
}
