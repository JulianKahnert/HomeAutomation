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

    /// Whether this status update is a transition INTO `.up` — from any not-up state, or from no
    /// prior status at all. This is the moment a full state resync is due: events dropped while
    /// disconnected are otherwise lost until the next organic change (#190 Findings 6/7).
    public func isReconnect(from previous: ConnectionStatus?) -> Bool {
        self == .up && previous != .up
    }
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
    private let onStuckExit: (@Sendable () -> Void)?

    private var reconnectionTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var graceTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?

    // MARK: - Watchdog / recovery tuning

    /// How often the stuck-non-up watchdog re-evaluates the cluster state.
    private static let watchdogInterval: Duration = .seconds(30)
    /// How long the cluster may stay below `.up` before the watchdog force-downs peer members.
    /// A healthy join completes in seconds; minutes below `.up` with a visible peer means the
    /// convergence deadlock (a stale member blocking gossip convergence, see #190 Finding 1).
    static let watchdogEvictionAfter: TimeInterval = 180
    /// Self-exit backstop threshold when this process had been `.up` before (warm wedge).
    static let watchdogSelfExitAfterWarm: TimeInterval = 600
    /// Self-exit backstop threshold when this process never reached `.up` — much longer than the
    /// warm threshold so a misconfigured peer cannot drive the container into a tight boot loop.
    static let watchdogSelfExitAfterCold: TimeInterval = 1200
    /// Adapter grace period after a lost connection (peer had been `.up` in this process).
    static let graceAfterConnectionLoss: Duration = .seconds(60)
    /// Adapter grace period when the peer never came up in this process. Long enough to survive a
    /// slow server boot and to configure the app interactively, but bounded so a never-up wedge
    /// boot still self-heals via restart (fresh node UID) instead of hanging forever.
    static let graceOnNeverUpBoot: Duration = .seconds(300)

    /// When this system was created — used to report uptime in diagnostics.
    private let bootDate = Date()
    /// When a reachable peer was last observed `.up` — used to report how long the cluster has been
    /// wedged. `nil` until the first `.up` is ever seen.
    private var lastUpDate: Date?
    /// Since when the connection has been continuously below `.up`. Reset to `nil` on every `.up`.
    /// `nil` while up; treated as `bootDate` before the first event arrives.
    private var notUpSince: Date?
    /// When the watchdog last force-downed members — re-arms only after another full
    /// `watchdogEvictionAfter`, so a legitimately (re)joining fresh peer gets time to come up.
    private var lastWatchdogEvictionAt: Date?

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

    /// Creates a fresh stream of connection status changes, seeded with the *current* value (so late
    /// subscribers never miss the latest state — unlike a plain broadcast) followed by live updates.
    /// Each call registers a new subscriber, so call it once per consumer.
    public func makeConnectionStatusStream() -> AsyncStream<ConnectionStatus> {
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
    ///     recover within a grace period. Used by the **adapter** to `exit(1)` so launchctl
    ///     restarts it with a fresh node UID. The grace period is short (60s) after a previous
    ///     `.up`, and longer (5min) on a never-up boot — but it always arms, so a boot into a
    ///     wedged cluster also self-heals via restart. The **server** passes `nil` — it stays
    ///     alive and heals as the cluster leader.
    ///   - onStuckExit: Optional closure called by the stuck-non-up watchdog as a last-resort
    ///     backstop: a peer is visible but the cluster has stayed below `.up` far beyond the
    ///     eviction phase. Used by the **server** to `exit(1)` so Docker's
    ///     `restart: unless-stopped` restarts the container with a fresh node UID. Gated on a
    ///     visible peer — a merely absent adapter never triggers it.
    ///   - logLevel: Log level for the underlying `swift-distributed-actors` system. The server
    ///     passes its configured level (driven by the `LOG_LEVEL` env) so cluster verbosity is set
    ///     once in docker-compose.
    public init(role: SystemRole, onDown: (@Sendable () -> Void)? = nil, onStuckExit: (@Sendable () -> Void)? = nil, logLevel: Logger.Level = .info) async {
        self.systemRole = role
        self.onDown = onDown
        self.onStuckExit = onStuckExit

        let settings = Self.makeClusterSettings(role: role, logLevel: logLevel)
        actorSystem = await ClusterSystem(role.name, settings: settings)

        Self.log.info("Cluster node started: role=\(role.name) node=\(actorSystem.cluster.node)")

        // Derive connection status from cluster events (membership + reachability).
        startStatusTask()

        // Periodic heartbeat so a wedged / never-up cluster is visible in the logs even when no
        // cluster events are firing.
        startHeartbeatTask()

        // SWIM-independent recovery from the convergence deadlock (#190 Finding 1). Runs for both
        // roles: SWIM stays silent in the real wedge (the new process on the same host:port answers
        // probes for the dead old UID), so no `.down` ever happens without this.
        startWatchdogTask()

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
    public static func makeClusterSettings(role: SystemRole, host: String? = nil, port: Int? = nil, logLevel: Logger.Level = .info) -> ClusterSystemSettings {
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
        settings.logging.logLevel = logLevel
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

    /// Derives the peer connection status for `selfNode` from a full membership, considering only
    /// peers (members other than self) and their reachability.
    public static func peerStatus(in membership: Cluster.Membership, selfNode: Cluster.Node) -> ConnectionStatus {
        let peers = membership.members(atLeast: .joining)
            .filter { $0.node != selfNode }
            .map { (status: $0.status, reachability: $0.reachability) }
        return decide(peers: peers)
    }

    /// Whether the local node has been moved to `.down`/`.removed` (e.g. evicted by the leader after a
    /// partition). This is terminal for the current node UID — the only recovery is a process restart
    /// (a fresh UID). `.leaving` is intentionally *not* treated as down (graceful, never self-initiated
    /// here). A `nil` status (self not yet in the membership) is not down.
    static func isLocalNodeDown(selfStatus: Cluster.MemberStatus?) -> Bool {
        guard let selfStatus else { return false }
        return selfStatus >= .down
    }

    static func isLocalNodeDown(in membership: Cluster.Membership, selfNode: Cluster.Node) -> Bool {
        isLocalNodeDown(selfStatus: membership.member(selfNode)?.status)
    }

    private func startStatusTask() {
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            guard let self else { return }
            let events = self.actorSystem.cluster.events
            let selfNode = self.actorSystem.cluster.node
            var membership = Cluster.Membership.empty
            for await event in events {
                switch event {
                case .snapshot:
                    Self.log.debug("Cluster event: \(event)")
                default:
                    // membershipChange / reachabilityChange / leadershipChange — always worth seeing.
                    Self.log.info("Cluster event: \(event)")
                }
                _ = try? membership.apply(event: event)

                // Terminal: our own node was evicted by the leader — restart for a clean rejoin.
                if Self.isLocalNodeDown(in: membership, selfNode: selfNode) {
                    await self.recoverFromLocalNodeDown()
                }

                let status = Self.peerStatus(in: membership, selfNode: selfNode)
                let summary = Self.membershipSummary(membership, selfNode: selfNode)
                await self.handleStatus(status, membershipSummary: summary)
            }
        }
    }

    private func handleStatus(_ status: ConnectionStatus, membershipSummary summary: String? = nil) {
        let changed = status != currentConnectionStatus
        currentConnectionStatus = status
        if status == .up {
            lastUpDate = Date()
            everConnected = true
            notUpSince = nil
        } else if notUpSince == nil {
            notUpSince = Date()
        }
        if changed {
            let suffix = summary.map { " members=[\($0)]" } ?? ""
            Self.log.info("Connection status: \(status)\(suffix)")
            for continuation in subscribers.values {
                continuation.yield(status)
            }
        }

        // Recovery is opt-in via `onDown` (adapter only). The server passes nil and never terminates
        // via this path (its backstop is the peer-gated watchdog self-exit).
        guard let onDown else { return }

        if status == .up {
            graceTask?.cancel()
            graceTask = nil
            return
        }

        // Peer not up: start a single grace timer (if one isn't already pending). It also arms on a
        // never-up boot — with a longer period — so a boot into a down server or a wedged cluster
        // recovers by restart (fresh node UID) instead of hanging in `.joining` forever.
        guard graceTask == nil else { return }
        let gracePeriod = Self.gracePeriod(everConnected: everConnected)
        graceTask = Task { [weak self] in
            try? await Task.sleep(for: gracePeriod)
            guard let self else { return }
            guard await self.currentConnectionStatus != .up else {
                Self.log.info("Reconnected during grace period.")
                return
            }
            Self.log.critical("Still disconnected after \(gracePeriod) grace period. Calling onDown handler.")
            onDown()
        }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
    }

    // MARK: - Stuck-non-up watchdog (#190 Finding 1)

    /// The adapter grace period before `onDown` fires: short after a lost connection, longer on a
    /// never-up boot. Pure so it can be unit-tested.
    static func gracePeriod(everConnected: Bool) -> Duration {
        everConnected ? graceAfterConnectionLoss : graceOnNeverUpBoot
    }

    /// Whether the watchdog should force-down a member. Every peer (non-self) that is not already
    /// at least `.down` is a candidate — **regardless of reachability**: in the verified wedge the
    /// stale dead-UID member stays REACHABLE (the new process on the same host:port answers its
    /// SWIM probes), which is exactly why the reachability-based downing never fires. Pure so it
    /// can be unit-tested.
    static func isWatchdogEvictionCandidate(status: Cluster.MemberStatus, isSelf: Bool) -> Bool {
        !isSelf && status < .down
    }

    /// What one watchdog tick should do. Pure value so the complete escalation ladder is
    /// unit-testable as timeline scenarios, without a running cluster.
    struct WatchdogDecision: Equatable, Sendable {
        /// Force `cluster.down(member:)` on the current eviction candidates.
        var shouldEvictPeers = false
        /// Escalate to the self-exit backstop (fresh process = fresh node UID).
        var shouldSelfExit = false

        static let noop = WatchdogDecision()
    }

    /// Decision function for one watchdog tick — the single place holding the escalation rules:
    ///
    /// - Nothing happens while `.up`, or while no peer is visible (an absent peer — adapter
    ///   switched off, server not yet deployed — is a legitimate long-lived state; only a peer
    ///   that is *present but stuck* below `.up` indicates the convergence wedge).
    /// - **Evict** once the cluster has been below `.up` for `watchdogEvictionAfter`, re-arming
    ///   only after another full window so a freshly rejoining peer gets time to come up.
    /// - **Self-exit** (backstop, wired on the server) after `watchdogSelfExitAfterWarm` when this
    ///   process had been `.up` before, or after the much longer `watchdogSelfExitAfterCold` on a
    ///   never-up boot (avoids tight boot loops on misconfiguration).
    static func watchdogDecision(
        connectionStatus: ConnectionStatus?,
        now: Date,
        notUpSince: Date?,
        bootDate: Date,
        lastEvictionAt: Date?,
        everConnected: Bool,
        hasPeers: Bool
    ) -> WatchdogDecision {
        guard connectionStatus != .up, hasPeers else { return .noop }
        let stuckDuration = now.timeIntervalSince(notUpSince ?? bootDate)

        var decision = WatchdogDecision()
        decision.shouldEvictPeers = stuckDuration >= watchdogEvictionAfter
            && (lastEvictionAt.map { now.timeIntervalSince($0) >= watchdogEvictionAfter } ?? true)
        decision.shouldSelfExit = stuckDuration >= (everConnected ? watchdogSelfExitAfterWarm : watchdogSelfExitAfterCold)
        return decision
    }

    private func startWatchdogTask() {
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.watchdogInterval)
                guard let self else { return }
                await self.runWatchdogCheck()
            }
        }
    }

    /// SWIM-independent recovery from a cluster that is stuck below `.up` (the convergence
    /// deadlock: one stale member with a current-looking seen-table blocks ALL `.joining → .up`
    /// promotions, and SWIM never reports it because the live process on the same host:port
    /// answers its probes). Two escalation phases:
    ///
    /// 1. After `watchdogEvictionAfter` below `.up`: force `cluster.down(member:)` on every peer —
    ///    manual downing is leader-independent and removes the stale member from the convergence
    ///    set. A downed live peer recovers on its own (the adapter rejoins with a fresh UID via
    ///    `recoverFromLocalNodeDown`; the server stays and re-admits the rejoining adapter).
    /// 2. As backstop (`onStuckExit`, server only): if a peer is visible but the cluster is still
    ///    not `.up` long after phase 1, exit the process so the container restart policy provides
    ///    a fresh node UID. Without this, `/health` stays 503 forever — Docker's
    ///    `restart: unless-stopped` does not act on an unhealthy container.
    /// Reads the actor state at one point in time and applies the pure decision function.
    /// Returns the stuck duration alongside for logging.
    private func evaluateWatchdog(hasPeers: Bool, now: Date) -> (decision: WatchdogDecision, stuckDuration: TimeInterval) {
        let decision = Self.watchdogDecision(
            connectionStatus: currentConnectionStatus,
            now: now,
            notUpSince: notUpSince,
            bootDate: bootDate,
            lastEvictionAt: lastWatchdogEvictionAt,
            everConnected: everConnected,
            hasPeers: hasPeers
        )
        return (decision, now.timeIntervalSince(notUpSince ?? bootDate))
    }

    /// `nonisolated` so the non-`Sendable` `Cluster.Membership` snapshot never crosses into the
    /// actor's isolation domain (mirrors `connectionDiagnostics()` and the reconnect loop). All
    /// escalation *rules* live in the pure `watchdogDecision` — this only observes and applies.
    nonisolated private func runWatchdogCheck() async {
        let snapshot = await actorSystem.cluster.membershipSnapshot
        let selfNode = actorSystem.cluster.node
        let peers = snapshot.members(atLeast: .joining).filter { $0.node != selfNode }

        let (decision, stuckDuration) = await evaluateWatchdog(hasPeers: !peers.isEmpty, now: Date())

        if decision.shouldEvictPeers {
            let candidates = peers.filter { Self.isWatchdogEvictionCandidate(status: $0.status, isSelf: false) }
            if !candidates.isEmpty {
                await recordWatchdogEviction()
                for member in candidates {
                    Self.log.warning("Watchdog: cluster below .up for \(Int(stuckDuration))s — forcing down member \(member) to break the convergence deadlock")
                    actorSystem.cluster.down(member: member)
                }
            }
        }

        if decision.shouldSelfExit, let onStuckExit {
            Self.log.critical("Watchdog: peer visible but cluster still not .up after \(Int(stuckDuration))s — self-exiting for a fresh node UID.")
            onStuckExit()
        }
    }

    private func recordWatchdogEviction() {
        lastWatchdogEvictionAt = Date()
    }

    /// Called when the local node was downed/removed by the leader. Terminal for this UID, so we
    /// hand off to `onDown` immediately (no grace) — the adapter restarts via launchctl with a fresh
    /// UID. The server passes `onDown == nil` and is unaffected (it is the leader and never downs itself).
    private func recoverFromLocalNodeDown() {
        guard let onDown else { return }
        Self.log.critical("Local node was downed/removed by the cluster leader — restarting for a clean rejoin.")
        onDown()
    }

    // MARK: - Observability

    /// Renders a compact one-line summary of all members (status/reachability), marking the local node
    /// with `*`. Pure so it can be used both inside the event loop and from the heartbeat/diagnostics.
    static func membershipSummary(_ membership: Cluster.Membership, selfNode: Cluster.Node) -> String {
        let members = membership.members(atLeast: .joining)
        guard !members.isEmpty else { return "<empty>" }
        return members.map { member in
            let selfMark = member.node == selfNode ? "*" : ""
            return "\(member.node.endpoint.host):\(member.node.endpoint.port)\(selfMark)=\(member.status)/\(member.reachability)"
        }.joined(separator: ", ")
    }

    /// A human-readable snapshot of the current connection state — peer status, how long since the
    /// peer was last `.up`, uptime, and the full membership. Used in `/health` 503 responses and the
    /// heartbeat log so a wedge is fully diagnosable from a single line. `nonisolated` so the
    /// non-`Sendable` `Cluster.Membership` stays within this context and never crosses into the actor's
    /// isolation domain (mirrors how the reconnect loop reads the snapshot).
    nonisolated public func connectionDiagnostics() async -> String {
        let snapshot = await actorSystem.cluster.membershipSnapshot
        let selfNode = actorSystem.cluster.node
        let status = Self.peerStatus(in: snapshot, selfNode: selfNode)
        let members = Self.membershipSummary(snapshot, selfNode: selfNode)
        let lastUp = await lastUpDate.map { "\(Int(Date().timeIntervalSince($0)))s-ago" } ?? "never"
        return "status=\(status) lastUp=\(lastUp) uptime=\(Int(Date().timeIntervalSince(bootDate)))s members=[\(members)]"
    }

    /// Logs the connection state once a minute. While `.up` it stays at `.debug` (quiet in production);
    /// while not up it logs at `.warning` with the full membership, so a wedge leaves an obvious,
    /// timestamped trail even when no cluster events are firing. Runs for both roles.
    private func startHeartbeatTask() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self else { return }
                await self.logHeartbeat()
            }
        }
    }

    private func logHeartbeat() async {
        let diagnostics = await connectionDiagnostics()
        if currentConnectionStatus == .up {
            Self.log.debug("Cluster heartbeat: role=\(systemRole.name) \(diagnostics)")
        } else {
            Self.log.warning("Cluster heartbeat (not up): role=\(systemRole.name) \(diagnostics)")
        }
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

                    // Poll-based fallback (in case the membership event never arrives): if our own node
                    // was evicted, restart rather than lingering as a zombie that believes it's connected.
                    if Self.isLocalNodeDown(in: snapshot, selfNode: selfNode) {
                        await self.recoverFromLocalNodeDown()
                    }

                    let status = Self.peerStatus(in: snapshot, selfNode: selfNode)

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
        heartbeatTask?.cancel()
        watchdogTask?.cancel()
        reconnectionTask = nil
        statusTask = nil
        graceTask = nil
        heartbeatTask = nil
        watchdogTask = nil
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
