# ADR-001: Replace DistributedCluster with a minimal WebSocket-based StarActorSystem

- Status: accepted (2026-07-26)
- Issue: #192 · Related: #190 (connection-resilience findings), PR #191 (watchdog mitigation, superseded by this)

## Context

Server (Vapor, Docker/Linux, well-known host:port, restarts rarely and briefly) and Adapter (macOS app, fragile, restarts often; possible iOS deployment without any restart mechanism) communicate via Swift distributed actors. The transport was [apple/swift-distributed-actors](https://github.com/apple/swift-distributed-actors) (`DistributedCluster`), a peer-to-peer cluster stack: SWIM failure detection, membership gossip, leader election, convergence-gated leader actions, node UIDs, association tombstones.

Recurring production incident ("cluster wedge", e.g. 2026-06-19): after an unluckily ordered restart, both nodes sit in `[joining]` forever, `/health` returns 503, all automations silently stop, and only a manual *ordered* restart (server, then adapter) recovers. PR #191 added an app-level watchdog (force-down peers stuck below `.up`, gated self-exits, grace timers) to compensate.

## Verified root cause and library gaps (as of `0041f6a` / 0.4.0, 2026-07)

A full code-level review of the library (3 independent analysis passes + manual verification) established the wedge chain and the gaps. **This list is the re-evaluation checklist: if these are fixed upstream, this ADR's premise should be re-examined.**

1. **`converged()` counts `.joining` members and ignores reachability** — `Sources/DistributedCluster/Cluster/MembershipGossip/Cluster+MembershipGossip.swift:136-158`. A dead "ghost" member whose gossip seen-table row never advances makes `converged()` return `false` forever. All leader actions (`.joining → .up` promotion, `.down` pruning) require `isLeader && converged()` (`ClusterShell+LeaderActions.swift:24-31`), so one silent member wedges the whole cluster. The maintainer's own FIXME on line 137; tracked upstream as [#412](https://github.com/apple/swift-distributed-actors/issues/412) (open since 2019). Note: a naive fix (dropping `.joining` from the set) is insufficient — `collectMemberUpMoves()` would promote the ghost to `.up`, which counts toward convergence again; a real fix also needs a promotion gate (reachable + seen-table currency).
2. **No "stuck below `.up`" timeout anywhere.** Downing is exclusively unreachability-driven (`TimeoutBasedDowningStrategy`) and leader-gated. A member stuck in `.joining` forever produces no downing directive.
3. **Gossip-merged members are never SWIM-monitored.** SWIM only monitors nodes that completed a handshake on this node (`ClusterShell.completeAssociation:122-126`). A member learned via membership gossip is never probed → never `.unreachable` → the downing strategy can never fire for it. "Reachable" in the wedge logs meant *never checked*, not *alive*.
4. **No `channelInactive` handling in the transport** (`TransportPipelines.swift` implements only `channelActive`). A dead TCP connection is invisible until SWIM ping timeouts; worse, the half-dead `.associated` association makes `beginHandshake` a no-op for that endpoint (`ClusterShell.swift:712-724`), so the survivor never re-handshakes on its own.
5. **Static discovery joins each endpoint once per process** (`DiscoveryShell.swift:91`, `subtracting(previouslyDiscoveredNodes)`), and the handshake backoff gives up permanently after 32 attempts (~90 s). If the peer is down longer at boot, no join ever happens again without app-level intervention.
6. **Crash landmine:** `fatalError("TODO; terminate the connection notify the membership!!!!")` on system-message redelivery exhaustion (`TransportPipelines.swift:559-562`) — reachable exactly when a peer dies with messages in flight.
7. **UID/tombstone semantics make manual recovery sharp-edged:** downing a *live* peer's UID tombstones it for 24 h (`associationTombstoneTTL`); the peer can only return with a fresh UID, i.e. a process restart. This is why the compensation layer needed `exit(1)`-based recovery paths.
8. **Replacement (same endpoint, new UID ⇒ old member downed) works but only on a fresh handshake** — fixed upstream in [#916](https://github.com/apple/swift-distributed-actors/pull/916) and [#1083](https://github.com/apple/swift-distributed-actors/pull/1083); it never fires for ghosts nobody re-handshakes toward (see 4/5).
9. **Maintenance reality:** between our pin `0041f6a` (2025-05) and `50e789fb` (0.4.0, 2026-06) there were 26 commits, essentially all CI/housekeeping. Issue #412 has been open since 2019. Betting on upstream fixes means maintaining a fork indefinitely.

Consequence: the app needed ~670 LoC of compensation (watchdog eviction, gated self-exits, grace timers, membership-inference for `/health`) on top of a ~43k-LoC dependency — and even then the wedge class was only *mitigated* (minutes of outage per incident), not eliminated.

## Options considered

1. **Use the library better** (trim PR #191, add `join()` nudge, server `onDown`): ~1 day, but the wedge class remains (heal times 3–20 min), the membership-inference layer stays, port 8888 stays unauthenticated.
2. **Patch the library, upstream the patches** (#412 fix + opt-in stuck-joining downing; both designed in detail): technically sound and upstream-desirable, but heals only the *known* variant (gaps 4–7 remain, so grace timers/backstops stay), saves only ~200 LoC locally, and realistically means an indefinitely maintained fork given upstream activity.
3. **Plain WebSocket + Codable message envelope (no distributed actors):** eliminates the wedge class structurally; most debuggable; but every new RPC method touches 4 hand-maintained places with runtime (not compile-time) failure modes, and the distributed-actor ergonomics are lost.
4. **Own minimal `DistributedActorSystem` over WebSocket ("StarActorSystem") — chosen.**
5. *Rejected:* [samalone/websocket-actor-system](https://github.com/samalone/websocket-actor-system) — closest existing package (TicTacFish-derived), but unmaintained (maintainer-acknowledged, issue #24), release build broken, no ping/pong keepalive (issue #14 — the exact mechanism we need), no auth story. Adopting it would mean forking a generic actor system on day one.

## Decision

Build **StarActorSystem**: a purpose-built `DistributedActorSystem` (~800 LoC incl. transports) for exactly this star topology, over WebSocket.

Key properties:

- **The connection *is* the membership.** No UIDs, no gossip, no leader, no convergence, no tombstones, no SWIM. Server restart ⇒ adapter socket errors ⇒ in-process reconnect with backoff. Adapter restart ⇒ new connection replaces the old (latest-connection-wins). Any restart order self-heals in ≤ ~30 s. The entire wedge class is structurally impossible, and the whole compensation layer (watchdog, eviction, grace timers, `exit(1)` recovery) is deleted, not ported.
- **Distributed-actor call sites stay unchanged.** `EntityAdapterable` keeps its `DistributedActor` constraint; `HomeManager` and both receiver actors are untouched apart from `typealias ActorSystem`. A future RPC method is one compiler-checked `distributed func` (option 3 would require 4 hand-edited places per method).
- **Transport:** authenticated Vapor WebSocket route on the existing port 8080 (Bearer token — closes the previously unauthenticated port-8888 hole); adapter uses `URLSessionWebSocketTask` with exponential backoff and ping/pong keepalive. iOS deployments recover in-process (no restart mechanism required).
- **Deliberate minimalism:** no generic distributed methods (hard error), no multi-peer support, no receptionist, no typed error round-tripping. Wire format is a small JSON envelope (`hello`/`call`/`reply`) with correlation IDs, per-call timeouts, and an additive-only evolution rule guarded by golden tests.

### Accepted risks and their guards

- **Mangled distributed-thunk identifiers are part of the wire format.** They are a deterministic function of module name + declaration signature (ABI-stable since Swift 5.7; the same property DistributedCluster relies on cross-node). Guards: the receivers' module name (`Adapter`) is frozen; a `hello(protocolVersion:)` handshake makes version skew loud; golden tests pin the thunk identifiers in CI.
- **Codable schema evolution between independently deployed builds** is now our responsibility: additive-only rule + golden wire-format tests (including old fixtures). Server (auto-deployed) and adapter (manually installed) can skew longer than expected — the hello handshake detects mismatches.
- **Invocation plumbing is opaque when it fails** (a decode error surfaces inside `executeDistributedTarget` with a mangled name). Guard: mandatory `.debug` envelope logging (callID, target, recipient).

## Consequences

- Deleted: `Sources/SharedDistributedCluster/` (~670 LoC), its tests (~380 LoC), the `swift-distributed-actors` dependency tree (~43k LoC + SWIM + service-discovery), port 8888, launchctl-restart-as-recovery.
- Added: `Sources/StarActorSystem/` (~800 LoC) + tests; server WS route; adapter transport wiring.
- Resync semantics: the adapter pushes its full HomeKit state on every transition into connected (covers events dropped while disconnected; transient pulses during an outage remain unrecoverable — bounded, known limitation; event buffering is a possible follow-up).
- One coupled deployment (server + adapter) at rollout; afterwards skew is detected by the hello handshake.
- Deferred decision: contributing the two library patches (a #412 convergence fix + opt-in stuck-joining downing) upstream as goodwill — no longer needed by this project.

## Re-evaluation triggers

Revisit this ADR if any of the following happens:

- [ ] Upstream fixes #412 (convergence without `.joining`) *including* a promotion gate for silent members
- [ ] Upstream adds a stuck-in-`.joining`/below-`.up` downing mechanism
- [ ] Upstream wires connection death (`channelInactive`) into unreachability/association teardown
- [ ] The `fatalError` redelivery landmine is removed
- [ ] swift-distributed-actors sees sustained feature development again (not just CI)
- [ ] This project genuinely needs ≥3 nodes with dynamic membership (a 3-node *star* does not count — StarActorSystem can carry that with a connection map)
- [ ] Swift's `Distributed` runtime changes thunk-identifier mangling (would break our wire format; watch Swift release notes; the golden thunk tests fail loudly in CI if so)
