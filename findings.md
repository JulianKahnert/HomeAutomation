# Code Review: Server ⇄ Adapter Reliability

**Date:** 2026-07-05 · **Scope:** `Sources/Adapter`, `Sources/Server`, `Sources/SharedDistributedCluster`, `Sources/HAApplicationLayer`, `Sources/HAImplementations`, `Sources/Shared`, `Apps/FlowKitAdapter` (branch `develop`) · **Focus:** reliability and resilience of the server ⇄ adapter connection — connection loss, restart in any order, self-healing without manual intervention.

**Method:** 6 parallel reviewers with distinct lenses (cluster lifecycle, adapter/HomeKit, server core, remote calls, concurrency, event pipeline) produced 81 raw findings, deduplicated to **40**. Every finding was then adversarially verified: 9 by an independent 3-verifier panel (correctness / realistic trigger / existing mitigation — each prompted to refute), 31 by direct source verification in the main review. **0 findings were refuted**; several were refined (corrections noted inline).

**Result: 1 critical, 21 major, 18 minor.**

---

## Executive summary

1. **The verified production-wedge root cause is still unmitigated (Finding 1, critical).** PR #183 shipped observability only. There is still no SWIM-independent stuck-non-up watchdog, no gated server self-exit, and the adapter's grace timer never arms on a never-up boot. The exact 2026-06-19 incident (both nodes stuck in `[joining]`, `/health` 503, automations silently stopped, manual ordered restart required) can recur unchanged.
2. **Events and commands are lost silently while the connection is down.** The adapter's event pump is consume-once with no buffer or retry (Finding 6); commands that fail inside the adapter can report success to the server (Finding 4); the failed-command retry loop is neutralized by the dedup cache (Finding 3); there is no state resync after reconnect in either direction (Finding 7) — divergence persists until the next organic change or the 6-hour HomeKit reset.
3. **The system cannot tell anyone it is degraded.** Adapter-down produces only `.warning` logs (no push), and the external dead-man HealthCheck keeps pinging healthily because it triggers on server-local clock events (Finding 22); HomeKit authorization loss (Finding 32) and the empty-config fallback (Finding 2) are log-only; `CriticalLogNotifier` consumes its hourly throttle slot even when the send fails (Finding 35).
4. **Restart durability gaps.** Automation on/off toggles are memory-only (Finding 18), in-flight automation sequences — turn-on-for-duration, window-notification waits — die with the process (Finding 19), and the `/tmp` config location works only because of an undocumented bind-mount contract in the external compose file (Finding 2).
5. **Long-uptime hygiene.** Unbounded streams and per-event unstructured tasks (Findings 24, 25), full-history table scans per event on an unindexed 90-day table (Finding 17), leaked timer tasks (Finding 23), and out-of-order event delivery poisoning the 2-hour entity cache (Finding 14).

---

## Critical (1)

### 1. Cluster-wedge self-healing still missing: no stuck-non-up watchdog, no gated server self-exit, adapter grace timer gated on everConnected, stale-member eviction cannot match the real wedge

**Severity:** critical · **Verified:** adversarial panel, 3/3 verifiers confirmed
**Location:** `Sources/SharedDistributedCluster/CustomActorSystem.swift:272, 339-346, 375-380`

```swift
guard everConnected, graceTask == nil else { return }
...
member.node.endpoint.port == serverEndpoint.port
    && (member.reachability == .unreachable || member.status >= .down)
```

Flagged independently by all 6 review lenses. The root cause of the recurring outage — a stale dead-UID member that stays REACHABLE and .joining (the new process on the same host:port answers SWIM probes for the old UID) blocks gossip convergence so the leader never promotes anyone to .up — remains unmitigated; PR #183 shipped observability only. Four independent gaps: (1) No SWIM-independent stuck-non-up watchdog exists anywhere (verified: only statusTask, heartbeatTask, graceTask, reconnectionTask; the heartbeat at lines 339-346 logs a .warning once a minute and takes no action). (2) The server has zero recovery path: Sources/Server/configure.swift:196-202 passes onDown: nil ('must NEVER terminate — hence no onDown handler'), so all not-up handling is skipped (`guard let onDown else { return }` at ~line 260); the only server-side consumer of connection status is the /health route (routes.swift:34-38) returning 503 — and Docker `restart: unless-stopped` does not act on unhealthy containers. (3) The adapter's only self-restart path (60s grace timer → onDown → exit(1), wired in Apps/FlowKitAdapter/FlowKitAdapterApp.swift:97-99) is gated on `everConnected`, which is set only after a .up in the CURRENT process — a boot into a down server or a wedged cluster never arms the timer; the 20s reconnect loop cannot compensate because `joined(endpoint:within:)` is a no-op while a (half-dead or wedged) association exists, and `isLocalNodeDown` needs >= .down which never happens in the wedge. (4) The only proactive downing (reconnect loop, lines 375-380) filters on `reachability == .unreachable || status >= .down` AND server endpoint only — by construction it never matches the reachable .joining stale member of the verified incident, and a stale ADAPTER UID (port 7777) lingering in the server's membership is never a candidate for anyone. The `RestartSystem` automation (Sources/HAImplementations/Automations/RestartSystem.swift:28) is a config-dependent scheduled exit(1), not wedge detection — and an unordered single-side restart is precisely what re-creates the wedge.

**Impact:** Exact recurrence of the 2026-06-19 production incident: after an unluckily-ordered restart, both nodes sit in [joining] forever, /health returns 503, the container is marked unhealthy but never restarted, all HomeKit-driven automations silently stop, and only a manual ORDERED restart (server, then adapter) recovers — up to 24h outage if left to a nightly RestartSystem, and only if configured.

**Recommendation:** Implement the two deferred plan steps in CustomActorSystem for BOTH roles: (1) a SWIM-independent stuck-non-up watchdog — if peer status has been < .up for N minutes (3-5), force `cluster.down(member:)` on every non-self member regardless of reachability (leader-independent), specifically downing older incarnations that share an endpoint with a different UID, forcing a fresh handshake; (2) a gated server self-exit as backstop — if still not .up after an escalation window (gated on lastUpDate != nil or a much longer cold-boot threshold to avoid boot loops), exit non-zero so `restart: unless-stopped` restarts the container with a fresh node UID; (3) arm the adapter grace timer on never-connected boots as well — drop the everConnected gate and scale the grace period instead (60s after a previous .up, several minutes from cold boot).

**Verifier corrections/refinements:**
- One precision nit only: the 60s grace timer is not literally the adapter's "only" self-restart path — recoverFromLocalNodeDown (CustomActorSystem.swift:292-296, invoked from the event loop at 235-237 and polled at 364-366) also calls onDown → exit(1). But it fires only when the local node reaches >= .down, which the finding itself correctly notes never happens in the wedge, so the conclusion is unaffected.

## Major (21)

### 2. Automation config persisted to container-ephemeral /tmp; load failure silently boots with ZERO automations

**Severity:** major · **Verified:** adversarial panel, 3/3 verifiers confirmed
**Location:** `Sources/Server/Controllers/HomeAutomationConfigService.swift:15, 49-59`

```swift
static let url = URL(fileURLWithPath: "/tmp/HomeAutomation-config.json")
...
} catch {
    log.error("Failed to parse config file - falling back to defaults: \(error)")
    return .init(location: Location(latitude: 53.14194, longitude: 8.21292), automations: [])
```

(server-core lens) The entire automation configuration (location + all automations) is persisted only to /tmp inside the Docker container. The Dockerfile declares no VOLUME for it, so unless the external docker-compose bind-mounts /tmp (not verifiable from this repo), every container RECREATION — image update via the docker-tag/docker-branches workflows, Renovate dependency bumps, `docker-compose down && up` — wipes the file. loadOrDefault() then silently falls back to an empty automation list and a hardcoded location. The fallback is logged at .error, not .critical, so CriticalLogNotifier (which only fires on .critical, CriticalLogNotifier.swift:79) sends no push alert. /health stays green (it checks DB + cluster only), so the server looks perfectly healthy while doing nothing.

**Impact:** Routine image upgrade silently disables ALL automations (and window notifications, live activities, sunrise/sunset logic tied to the real location) until someone notices and manually re-POSTs /config. Matches the 'silent stop of automations requiring manual intervention' failure class.

**Recommendation:** Move the config file to a dedicated path (e.g. /app/data/HomeAutomation-config.json) documented to be volume-mounted, or persist the config in MySQL (a table survives recreation and is already a hard dependency). Log the fallback at .critical so a push notification fires, and consider refusing to overwrite a previously non-empty config with the empty default on the next save().

**Verifier corrections/refinements:**
- Finding is fully correct; one nuance strengthens it: the recommendation to "log the fallback at .critical" would still not fire a push for this event, because loadOrDefault() runs at configure.swift:212 before CriticalLogNotifier.shared.configure(notificationSender:) at line 218, and the notifier silently drops events while unconfigured (guard at CriticalLogNotifier.swift:29). The fix needs durable persistence (volume path or MySQL) plus an alert emitted after push infrastructure is ready. Also note /tmp survives a plain docker restart; only container recreation (image upgrade, down/up) wipes it — as the finding already states.
- The config file is NOT wiped by container recreation: the deployment compose (HomeAutomation-config/docker-compose.yml and the public config-template repo, app/migrate/revert services) bind-mounts ./docker-volumes/home-automation:/tmp, so routine image updates preserve /tmp/HomeAutomation-config.json. The valid residual finding: loadOrDefault() (HomeAutomationConfigService.swift:49-59) silently falls back to ZERO automations + hardcoded location on ANY load/decode failure — realistic via Codable schema drift of AnyAutomation across image upgrades, file corruption from the non-atomic data.write(to:) in save() (line 46), or host bind-mount issues — logged only at .error so CriticalLogNotifier (fires only on .critical, CriticalLogNotifier.swift:79) sends no alert, and /health stays green. Recommended fixes still apply: log the fallback at .critical, write atomically, and/or persist config in MySQL.
- Container recreation does not wipe the config in the real deployment (the external docker-compose bind-mounts /tmp to the host). The remaining real issues: (1) the /tmp-must-be-volume-mounted contract is implicit and documented nowhere in this repo (Dockerfile has no VOLUME, docs/setup-server.md is silent), so any redeployment without that mount silently loses all automations; (2) the silent fallback path is still reachable via file corruption — save() uses non-atomic `data.write(to: Self.url)` (HomeAutomationConfigService.swift:46) — or Codable schema drift in ConfigDTO/AnyAutomation across versions, in which case the server boots with zero automations, logs only .error (no push notification), keeps /health green, and requires a manual POST /config to recover. This is a no-alerting silent-degradation failure mode: major, not critical.

### 3. Failed-command retry is a guaranteed no-op: the dedup cache marks commands 'executed' before execution, so the 5s retry is skipped as a duplicate

**Severity:** major · **Verified:** adversarial panel, 3/3 verifiers confirmed
**Location:** `Sources/HAApplicationLayer/HomeManager.swift:91-116 (cache insert: Sources/HAApplicationLayer/Managers/ActionLogManager.swift:51-54)`

```swift
let hasCacheHit = await actionLogManager.log(action: action)
if hasCacheHit { log.info("Skipping duplicate command: [\(action)]"); return }
...
} catch { ... if addToFaliedActions { failedActions[entityId] = action } }
```

Found by 4 lenses (server-core, remote-calls, concurrency, event-pipeline). ActionLogManager.log() inserts the action into the 2-minute commandCache BEFORE the adapter call (ActionLogManager.swift:52-53), and nothing removes the entry when perform() throws. The failed action lands in failedActions and the retry loop (HomeManager.swift:44-53) re-runs it ~5s later via perform(action, addToFaliedActions: false) — but that retry calls log() again, gets a guaranteed cache hit on the entry written during the failed attempt, logs 'Skipping duplicate command' and returns WITHOUT touching the adapter. Because addToFaliedActions is false, the action is not re-queued either: every failed command is retried exactly zero times, and identical automation re-issues are suppressed for 2 minutes. Drift invalidation (#184) cannot rescue it — the device never received the command, so no contradicting state event arrives to evict the cache entry. Two aggravations: failedActions is keyed by EntityId only (line 24), so a failed turnOn and setBrightness for the same entity overwrite each other; and Timer.publish aligns its first tick to the next minute boundary regardless of the 5s interval (Sources/Shared/Timer.swift:18-20), so the (already broken) first retry can take up to 60s.

**Impact:** Any command issued during an adapter restart, network blip, 15s remote-call timeout, or HomeKit hub hiccup is silently lost (light stays on, valve stays open, door stays unlocked) AND blocked from re-issue for 2 minutes — the 5-second retry mechanism that is supposed to cover exactly this window is dead code. E.g. 'turn heating off, window opened' lost this way leaves heating on until the next state event for that entity happens to contradict the phantom cached command.

**Recommendation:** Remove the action from the commandCache when adapter.perform() throws (add ActionLogManager.invalidate(action:) and call it in the catch block before adding to failedActions), or only insert into the cache after successful execution. Make the retry loop re-add still-failing actions with a bounded retry count/backoff instead of one-shot addToFaliedActions: false. Key failedActions by (EntityId, actionName) like CommandCacheKey. Add a unit test: perform fails → retry tick → adapter.perform must be invoked again.

**Verifier corrections/refinements:**
- The only overstatement: "Drift invalidation cannot rescue it — no contradicting state event arrives" is too absolute. The adapter pushes a full snapshot of subscribed characteristics on startup and HomeKit delegate callbacks (Sources/Adapter/HomeKitAdapter+Delegates.swift:109-126), which flows through EventProcessingJob → addEntityHistory → invalidateContradictedCommands (EventProcessingJob.swift:26-31), so after an adapter restart the phantom cache entry can be evicted and the automation may re-fire. This rescue is unreliable though — it does not cover network blips/remote-call timeouts (no snapshot without a delegate event), and eviction re-triggers automations only via the contradicting entity's own event, which may not be the automation's trigger entity. The core claim stands: the dedicated failed-command retry mechanism is dead code, and every failed command is retried zero times.
- Finding is correct except one aggravation is overstated: Timer.publish (Sources/Shared/Timer.swift:18-29) aligns only the first tick after stream creation to the next minute boundary; the stream is created once in HomeManager.init and then ticks every 5s for the process lifetime, so the up-to-60s retry delay applies only to failures within the first minute after server start, not to every failure. The core claim (retry is a guaranteed no-op and failed commands are silently lost + suppressed for 2 minutes) stands regardless.
- Two minor nuances, neither changing the verdict: (1) on adapter (re)start the adapter yields a full state snapshot (HomeKitAdapter+Delegates.swift:110-127), so in that one scenario drift invalidation can evict the phantom cache entry once the contradicting state arrives — but this only re-permits issuance; the lost command is still never re-executed without a fresh automation trigger, and the 2-min TTL typically expires before reconnect anyway. (2) The up-to-60s first-tick delay applies only to failures within the first minute after process start; thereafter ticks fire every 5s (moot, since the retry is a no-op regardless).

### 4. HomeKitAdapter.perform() silently returns success when the characteristic cannot be resolved (assertionFailure is a release no-op)

**Severity:** major · **Verified:** adversarial panel, 3/3 verifiers confirmed
**Location:** `Sources/Adapter/HomeKitAdapter.swift:70-77 (same pattern at 90-94, 100-104, 120-134)`

```swift
guard filteredCharacteristics.count == 1,
      let characteristic = filteredCharacteristics.first else {
    log.error("Failed to get characteristic")
    assertionFailure()
    return
}
```

Found by 5 lenses. In release builds `assertionFailure()` is a no-op, so when the entity cannot be resolved (0 matches — e.g. HomeKit not yet loaded / homes momentarily empty — or 2+ matches), or when brightness/color-temperature metadata is nil, or in the scene-authoring paths (lines 120-134), perform() returns WITHOUT throwing. The distributed call therefore reports success to the server: HomeManager only adds to failedActions when perform THROWS (HomeManager.swift:104-116), the command stays in the 2-minute dedup cache marked as executed, and drift-invalidation from PR #184 never fires because the device state never changed. This window is not rare — it is systematically opened by the 6-hour HMHomeManager reset publishing an empty homes list (see separate finding) and by HomeKit daemon hiccups or accessory removal.

**Impact:** Silent command loss with a success response: lights/valves/locks not actuated while the server believes they were — the server's entire failure-handling chain (failedActions retry, error logs, drift-invalidation reasoning) is bypassed, with zero signal.

**Recommendation:** Throw a typed error (e.g. HomeKitAdapterError.characteristicNotFound(entityId) or OptionalError.notFound) from every guard-return path in perform() so the error propagates over the distributed call into HomeManager's catch and the failedActions retry/alerting engages.

**Verifier corrections/refinements:**
- The finding is accurate except for one overstatement: impact is not literally "zero signal" — the adapter emits log.error("Failed to get characteristic") at HomeKitAdapter.swift:74. Corrected claim: there is an adapter-local log line only; no error propagates over the distributed call, so the server sees success and its entire failure chain (failedActions retry, error logs, drift-invalidation) is bypassed.
- One sub-claim is imprecise: drift-invalidation is not fully bypassed. updateEntities() (HomeKitAdapter+Delegates.swift:110-127) re-yields ALL subscribed characteristic states on every home-delegate event (including the homes reload ending the empty-homes window), and a state contradicting the cached command (e.g. isDeviceOn == false vs cached .turnOn, HomeManagableAction+Contradiction.swift:37-39) invalidates the cache via HomeManager.swift:148; the dedup cache also expires after 2 minutes (ActionLogManager.swift:32). So the dedup blackout is bounded and re-issue can happen if the automation re-triggers — the command loss is real and unsignalled, but usually not permanent. Core claim (silent success, failedActions retry and server-side error logging bypassed) is fully correct.
- Two secondary claims are overstated: (1) not literally "zero signal" — the adapter logs log.error("Failed to get characteristic") locally, but nothing propagates to the server, which records success; (2) drift-invalidation is not fully bypassed — after homes reload, updateEntities() (HomeKitAdapter+Delegates.swift:110-127) re-yields all subscribed items even unchanged, flowing via EventProcessingJob.swift:27 into invalidateContradictedCommands (HomeManager.swift:148), which clears the contradicted cached command and allows re-issue when the automation re-evaluates. This gives eventual self-correction for recurring state-triggered automations only; time-based/one-shot commands (e.g. scheduled lockDoor) remain silently lost until their next trigger. Core finding and major severity stand.

### 5. 6-hourly HMHomeManager reset publishes the new manager's empty homes list — recurring blind window; first reset fires ~60s after launch, not after 6 hours

**Severity:** major · **Verified:** adversarial panel, 3/3 verifiers confirmed
**Location:** `Sources/Adapter/HomeKitAdapter+Delegates.swift:36-46`

```swift
log.info("Resetting HMHomeManager to create a new HomeKit connection")
self.manager = HMHomeManager()
self.manager.delegate = self
await homesPublisher.send(self.manager.homes)
```

Found by 4 lenses. A freshly constructed HMHomeManager reports an empty `homes` array until its delegate fires homeManagerDidUpdateHomes (seconds to tens of seconds, longer when homed is slow — the very hiccup this reset works around). Sending that empty array into homesPublisher means getHomes()/getCharacteristics() return [] for the whole window: getAllEntitiesLive() returns 0 entities (spurious /config validation failures on the server) and perform() hits the silent-drop path from the previous finding — commands silently no-op. Worse, because Timer.publish fires its FIRST tick at the next minute boundary (Sources/Shared/Timer.swift:18), the first reset happens within ~60s of every app start, racing the initial home load and subscription setup. If the new manager never delivers homes (HomeKit auth revoked, homed hiccup), the publisher stays poisoned with [] forever while the cluster still reports .up — a permanent zombie that looks connected. Additionally, `guard let self else { continue }` (line 38) keeps the reset loop alive forever after the owner deallocates, leaking a timer task per discarded HomeKitAdapter, and events from the old manager's home objects are lost during each reload window.

**Impact:** Recurring blind window (at startup + every 6h) where all automation commands vanish with reported success and live entity queries return nothing; a single failed home reload turns the adapter into a permanent zombie.

**Recommendation:** Do not `send(self.manager.homes)` on reset — keep the last-known homes until the new manager's homeManagerDidUpdateHomes delivers a non-empty replacement (or gate the send on !homes.isEmpty). Fix Timer.publish so the first tick is now + duration. Add a watchdog: if no homes arrive within N minutes of a reset, log critical / restart. Change `continue` to `return` in the weak-self guard.

**Verifier corrections/refinements:**
- Finding is essentially fully correct. One softening nuance: dropped commands are not necessarily lost forever — the server-side drift-invalidation from commit #184 (Sources/HAApplicationLayer/HomeManager.swift:148, ActionLogManager.invalidateContradictedCommands) lets the automation engine re-issue a silently dropped command once a contradicting state event for that entity arrives; until then, however, the actionLogManager dedupe cache (HomeManager.swift:93-98) actively suppresses identical retries, making the drop sticky. Recovery is therefore delayed/unreliable rather than nonexistent — which still matches the "major" calibration exactly.
- Finding stands at major with one correction: the "permanent zombie / poisoned forever" tail scenario is overstated — the publisher heals on any subsequent delegate callback (homeManagerDidUpdateHomes / didUpdate status, HomeKitAdapter+Delegates.swift:156-165) including from later 6-hourly resets, and the server's drift-invalidation layer (HomeManager.swift:137-151) can belatedly re-issue commands dropped in the blind window. The confirmed core issue is a recurring blind window of seconds (at ~60s after every launch, then every 6h) during which perform() silently no-ops with reported success, getAllEntitiesLive() returns 0 entities, and HomeKit events can be lost — with no empty-homes guard, no watchdog, and no alerting.
- Two small refinements: (a) the first reset fires at the next wall-clock minute boundary, i.e. 0-60s after launch (not fixed ~60s); (b) impact is partially softened by the server's 2h entityCache for findEntity (HomeManager.swift:76-82) and by #184's drift invalidation (HomeManager.swift:148) which lets automations re-issue a dropped command after a later contradicting state event — but /config validation (routes.swift:73 via getAllEntitiesLive) and perform() always hit the adapter live, so the recurring blind window and silent command drops remain real and unalerted.

### 6. Entity events silently dropped while the server is unreachable — no buffering, no retry; boot-time full-state push races receptionist discovery

**Severity:** major · **Verified:** adversarial panel, 3/3 verifiers confirmed
**Location:** `Apps/FlowKitAdapter/FlowKitAdapterApp.swift:131-147`

```swift
// this might be very slow, when no server is connected
try await receiver?.process(event: .change(entity: entity))
} catch {
    Self.log.error("Failed to process event: \(error)")
}
```

Found by 5 lenses. The single event pump consumes each entity from the stream exactly once. If `receiver` is nil (server never seen / not yet discovered) the optional-chained call is a silent no-op; if the remote call throws (server restarting, network blip, 15s remote-call timeout against a stale ref) the catch only logs. Either way the event is permanently discarded — there is no local queue, no re-enqueue, no retry. Crucially, at adapter boot HMHomeManager fires homeManagerDidUpdateHomes within seconds and updateEntities() floods the FULL initial home state into entityStream (HomeKitAdapter+Delegates.swift:110-127) — usually before the cluster join + receptionist gossip completes — so the entire initial snapshot is dropped. Verified: the server has no compensating pull either (getAllEntitiesLive is only invoked from POST /config validation, routes.swift:73, and UpsertScene).

**Impact:** Every sensor edge during a server restart/outage/blip is lost forever. A contact sensor that opens during the outage and stays open is invisible to the server until it changes AGAIN — window-open notifications and Live Activities stay wrong, automations (heating, MotionAtNight) evaluate stale DB state indefinitely.

**Recommendation:** Hold events in a bounded ring buffer (newest-per-EntityId) while the receiver is unavailable and flush it when connectionStatus transitions to .up / a receiver resolves; at minimum do not consume-and-drop — retry the current event with backoff until a receiver responds or a newer event for the same EntityId supersedes it.

**Verifier corrections/refinements:**
- Core finding stands: events are consumed-once and dropped on nil receiver or throwing remote call, with no buffering/retry, and the boot-time full-state push does race receptionist discovery. But (1) the nil-receiver path is not silent — each event retries system.lookup() and logs "Failed to resolve HomeEventReceiver actor" (FlowKitAdapterApp.swift:136-141); (2) persistent sensor states are not lost "indefinitely": updateEntities() re-yields the FULL current snapshot on every HomeKit delegate event (accessory reachability/name/service changes) and at latest every ~6 hours via the HMHomeManager reset (HomeKitAdapter+Delegates.swift:36-46 → homeManagerDidUpdateHomes → updateEntities), so a stuck-open contact sensor becomes visible at the next full re-push (worst case ~6h). Permanently lost are transient edges (motion pulses, button presses, open-then-closed transitions) that revert within the outage window — these drive automations and never reappear in later snapshots.
- The consume-and-drop pump with no buffering/retry and no server-side state pull is real, but dropped events are not lost "forever": the adapter re-floods the full entity snapshot on every updateEntities() trigger — the 6-hour HMHomeManager reset (HomeKitAdapter+Delegates.swift:36-46) and any home/accessory delegate event — so persisting stale state (open window, automations on stale DB) lasts up to ~6 hours, not indefinitely. Transient edges (motion pulses, short door openings) during an outage are genuinely unrecoverable. The nil-receiver path also logs ("Failed to resolve HomeEventReceiver actor", FlowKitAdapterApp.swift:140), and the boot-time snapshot drop is a timing race (lookup is retried per event), not a guaranteed full-snapshot loss. Severity remains major: missed/lost events with hours-long stale automation inputs and no alerting.
- The drop mechanism is exactly as described (consume-once, silent no-op on nil receiver, log-only catch, no buffering/retry, no server pull), but stale state is not invisible "indefinitely"/"forever": the adapter re-floods the FULL current HomeKit state via updateEntities() on every 6-hour HMHomeManager reset (HomeKitAdapter+Delegates.swift:36-46) and on any accessory delegate churn, and a >60s server outage restarts the adapter (grace timer + exit(1)) which re-floods at boot. So a missed edge (e.g. window opened during an outage that stays open) is stale for up to ~6 hours — bounded, self-healing, but still hours of wrong window notifications/Live Activities and automations evaluating stale state, with the boot-time re-flood itself exposed to the same receptionist-discovery race. Severity remains major.

### 7. No state resync after reconnect in either direction — server and HomeKit reality diverge until the next organic change or the 6-hour reset

**Severity:** major · **Verified:** adversarial panel, 3/3 verifiers confirmed
**Location:** `Apps/FlowKitAdapter/FlowKitAdapterApp.swift:113-118`

```swift
statusObservationTask = Task {
    for await status in await system.makeConnectionStatusStream() {
        connectionStatus = status
    }
}
```

(event-pipeline lens; also raised inside the drop findings of 3 other lenses) The adapter observes connection-status transitions but uses them ONLY to update the SwiftUI UI. Nothing triggers updateEntities() (the full-state re-push) when status transitions to .up after a disconnect — it is invoked only from HomeKit delegate callbacks and the 6-hourly HMHomeManager reset (HomeKitAdapter+Delegates.swift:142). On the server side, nothing calls getAllEntitiesLive() when an adapter (re)joins. So after any server restart or connection outage (during which events were dropped, see previous finding), the server continues operating on pre-outage data; the only bounds on divergence are the next organic HomeKit change per entity or the 6h reset.

**Impact:** A window opened during a 2-minute server redeploy stays 'closed' on the server for up to hours; automations (heating, notifications) act on wrong state with no indication anything was missed. This is what makes the drop-while-disconnected finding hours-long instead of seconds-long.

**Recommendation:** Subscribe to makeConnectionStatusStream() in the adapter and trigger updateEntities() (debounced full snapshot push) on every transition to .up — this makes reconnect self-correcting regardless of what was dropped. Alternatively/additionally have the server call getAllEntitiesLive() when the receptionist listing yields a new adapter and feed the result through addEntityHistory.

**Verifier corrections/refinements:**
- The core claim stands, but the impact example overstates one path: for outages exceeding the 60s grace period (including the cited 2-minute server redeploy), the adapter self-restarts (CustomActorSystem.swift:273-282 grace timer → onDown → exit(1) at FlowKitAdapterApp.swift:97-99, launchctl KeepAlive), and the fresh boot's homeManagerDidUpdateHomes triggers a full updateEntities() push — an indirect resync. That path is unreliable though: the boot-time full push races cluster join (per-event lookup returns nil / process() throws → events dropped, FlowKitAdapterApp.swift:136-147) and nothing re-pushes afterwards. The hours-long divergence is guaranteed only for blips shorter than / recovering within the 60s grace, and whenever the boot-time push loses the race — in both cases divergence persists until the next organic per-entity change or the 6h reset.
- The finding slightly understates one timing-dependent mitigation: for outages longer than the 60s grace period (CustomActorSystem.swift:272-282), the adapter's onDown exit(1) restarts it and the relaunch's homeManagerDidUpdateHomes → updateEntities() pushes a full snapshot — an accidental resync IF the server is back before HomeKit homes load. In the common cases (blip/redeploy <60s: no restart at all; ~2min redeploy: restarted adapter's snapshot is pushed ~60-70s into the outage to a nil receiver and dropped, and everConnected resets so no second restart) no resync occurs, so the core claim and hours-long divergence window stand.
- The finding is correct but omits one partial mitigation: the adapter's onDown self-restart (FlowKitAdapterApp.swift:97-99, exit(1) after the 60s grace in CustomActorSystem.swift:272-283, relaunched via launchctl KeepAlive) produces a full updateEntities() push on fresh boot, making reconnects self-correcting when the disconnect exceeds 60s AND the server is reachable when the restarted adapter boots (adapter crash, adapter-side blip >60s). The stated impact holds for the two uncovered cases: (a) blips shorter than the 60s grace (no restart, no resync), and (b) server restarts/redeploys — the restarted adapter boots while the server is still down, its boot snapshot is silently dropped (FlowKitAdapterApp.swift:136-147, receiver nil → item skipped), and the fresh process never restarts again because the grace timer is gated on everConnected (CustomActorSystem.swift:272), so divergence persists until the next organic HomeKit change or the 6h reset.

### 8. onDown = exit(1) has no restart mechanism on iOS deployments

**Severity:** major · **Verified:** adversarial panel, 2/2 verifiers confirmed
**Location:** `Apps/FlowKitAdapter/FlowKitAdapterApp.swift:97-99`

```swift
let system = await CustomActorSystem(role: .homeKitAdapter(serverAddress: serverAddress), onDown: {
    exit(1)
})
```

(cluster-lifecycle lens) The adapter's entire disconnect-recovery design assumes something relaunches the process after exit(1). docs/setup-FlowKitAdapter.md documents two supported deployments: macOS (launchd KeepAlive re-running `open`) and iOS/iPadOS via Guided Access. Guided Access does not relaunch a terminated app, and iOS has no launchd equivalent — so on an iOS-deployed adapter, every network blip longer than the 60s grace period converts a transient outage into a permanent one. The same applies to fatalError/crash paths.

**Impact:** On an iOS/iPadOS adapter, a single >60s server restart or Wi-Fi blip permanently kills the HomeKit bridge (automations stop) until someone manually reopens the app.

**Recommendation:** On iOS, do not exit(1); instead fully tear down and recreate the CustomActorSystem in-process (the shutdown() + init path already exists in FlowKitAdapterApp for address changes) to get a fresh node UID. Alternatively gate the exit(1) recovery on #if os(macOS) and use the recreate path elsewhere; and document that iOS Guided Access cannot auto-recover.

**Verifier corrections/refinements:**
- The finding slightly understates the trigger window: besides the 60s grace path, blips as short as ~10s can also permanently kill an iOS-deployed adapter — the server downs unreachable members after 10s (CustomActorSystem.swift:163), and once the adapter learns its UID was downed it calls onDown()/exit(1) immediately with no grace (CustomActorSystem.swift:292-296). Severity stays major (not critical) only because the primary documented/production deployment is macOS+launchd, which does relaunch; the permanent-outage mode is conditional on choosing the iOS deployment.

### 9. fatalError in updateEntities() is reachable at runtime and crashes the whole adapter on a transient nil accessory back-reference

**Severity:** major · **Verified:** adversarial panel, 2/2 verifiers confirmed
**Location:** `Sources/Adapter/HomeKitAdapter+Delegates.swift:82-84`

```swift
guard let accessory = characteristic.service?.accessory else {
    fatalError("Could not set delegate on accessory")
}
```

Found by 5 lenses. updateEntities() snapshots all characteristics, then iterates asynchronously (awaiting enableNotification per characteristic). `characteristic.service`/`service.accessory` are weak-ish HomeKit back-references that legitimately become nil while an accessory is being removed, blocked, or while homed is flapping — and update(homes:) is invoked from many delegate callbacks including didEncounterError and reachability changes, i.e. precisely when HomeKit is unstable. One nil reference kills the entire adapter process. The DEBUG-only assertionFailure() at line 106 similarly crashes debug runs on the common 'device unavailable' notification error.

**Impact:** Full adapter crash on an ordinary HomeKit topology change or daemon hiccup, dropping the entity-stream backlog and in-flight commands. On macOS this causes launchd restart churn (fresh-UID rejoin, event gap) and a crash loop if the condition persists; on an iOS Guided-Access deployment there is no auto-restart — permanent outage.

**Recommendation:** Replace fatalError with `log.error(...); continue` — skip the orphaned characteristic (the next delegate-triggered scan picks up the corrected topology). Remove/soften the assertionFailure in the notification-error catch.

**Verifier corrections/refinements:**
- Finding stands as written; only the "crash loop if the condition persists" clause is speculative — the nil back-reference is transient, so a single crash + launchd restart (with fresh-UID rejoin and an event gap) is the likely macOS outcome rather than a sustained crash loop.

### 10. Stale HomeEventReceiver reference reused until receptionist catches up; inner listing task is unstructured, leaks on teardown, and is never re-established

**Severity:** major · **Verified:** confirmed in main review against source
**Location:** `Apps/FlowKitAdapter/FlowKitAdapterApp.swift:122-144`

```swift
var receiver: HomeEventReceiver?
Task {
    for await foundReceiver in await system.listing(of: .homeEventReceiver) {
        ...
    }
}
```

Found by 3 lenses. After a server restart, `receiver` still points at the dead remote actor. The recovery `if receiver == nil { receiver = await system.lookup(...) }` never runs because receiver is non-nil, so every event first burns the 15s remoteCall timeout and is then dropped, until the receptionist listing eventually yields the new server's receiver. The listing loop itself is a nested unstructured Task — it is NOT cancelled when entityObservationTask is cancelled during teardown (teardownActorSystem, lines 82-91), so every server-address change leaks a listing subscription that keeps the old CustomActorSystem and captured references alive; and if the listing stream ever terminates it is never re-established, permanently disabling receiver refresh while the outer loop keeps trying the dead ref.

**Impact:** After each server restart, entity events are delayed 15s each and dropped until receptionist gossip converges; if the listing stream dies, event forwarding degrades permanently (one dropped event per 15s) with only error logs; teardown leaks accumulate across reconfigurations.

**Recommendation:** Set `receiver = nil` in the catch block so the next event re-resolves via lookup; make the listing iteration a child of the outer task (task group, or hold the inner task and cancel it in a defer) so cancellation propagates; log and restart the listing loop if it finishes.

**Verifier corrections/refinements:**
- Within one session the listing task is re-created by each `initializeActorSystem()`; the leak occurs on teardown (server-address change). A listing stream that terminates mid-session is never restarted and its death is not logged.

### 11. .task(id:) cancellation race can create a second ClusterSystem while the first leaks un-shutdown — a zombie node on port 7777 that keeps answering SWIM

**Severity:** major · **Verified:** confirmed in main review against source
**Location:** `Apps/FlowKitAdapter/FlowKitAdapterApp.swift:74-77`

```swift
await teardownActorSystem()

try? await Task.sleep(for: .seconds(1))
await initializeActorSystem()
```

Found by 2 lenses (concurrency, adapter-homekit). SwiftUI's .task(id: serverAddress) cancels the previous task when the id changes (or the window closes/reopens) but does not wait for it to finish. Cancellation during the sleep is swallowed by `try?` and the body never checks Task.isCancelled, so the cancelled run still executes initializeActorSystem(), creating ClusterSystem A and setting self.actorSystem = A — concurrently with the replacement task's own teardown+init creating system B and overwriting self.actorSystem. System A is never shutdown(): its statusTask strongly retains it (CustomActorSystem.swift:219-220 upgrades [weak self] to a strong ref for the loop's lifetime), so it lives on, bound to (or fighting for) port 7777 and answering SWIM probes with a UID the server considers a member — precisely the stale-reachable-member ingredient of the production wedge.

**Impact:** A server-address edit or window re-appearance at the wrong moment leaves a zombie cluster node running inside the adapter process: bind failure for the new system or a live duplicate-UID node that can wedge the cluster. Requires app restart to clear.

**Recommendation:** Check Task.isCancelled after the sleep (`guard !Task.isCancelled else { return }`, and again after initializeActorSystem's awaits before publishing state) or use `try Task.sleep` and return on throw; alternatively serialize teardown/init through a single long-lived coordinator actor keyed by generation so a stale run can never install a system.

**Verifier corrections/refinements:**
- The trigger (serverAddress change / scene re-run) is rare, but the consequence is exactly the wedge amplifier from the incident history: a second system competing for port 7777, with the un-shutdown one able to answer SWIM probes for a dead UID.

### 12. Every delegate callback spawns an uncoalesced full-home updateEntities() rescan feeding an unbounded entity stream drained at up to 15s per event

**Severity:** major · **Verified:** confirmed in main review against source
**Location:** `Sources/Adapter/HomeKitAdapter+Delegates.swift:133-146 (stream: Apps/FlowKitAdapter/FlowKitAdapterApp.swift:102-103)`

```swift
Task {
    await homesPublisher.send(homes)
    await updateEntities()
}
...
AsyncStream.makeStream(of: EntityStorageItem.self, bufferingPolicy: .unbounded)
```

Found by 4 lenses. update(homes:) is called from ~10-12 delegate methods (homeManagerDidUpdateHomes, accessoryDidUpdateReachability, name/firmware updates, didEncounterError, ...), each spawning a new unstructured Task running updateEntities(): a serial walk over ALL characteristics awaiting enableNotification per characteristic (network round-trips), a task-group read of every subscribed characteristic, then a re-yield of the FULL state set into entityStream. There is no coalescing, serialization, or cancellation of the previous run — a hub reboot flapping N accessories' reachability produces N overlapping full-home scans, request storms against flaky accessories, and interleaved enableNotification calls that can leave subscriptions in the wrong state. Meanwhile the stream is explicitly .unbounded and the single consumer forwards serially at up to 15s per event while it holds a stale receiver ref, so during outages/delegate storms the backlog grows without bound and is later replayed as stale, duplicated snapshots with old timestamps.

**Impact:** During HomeKit instability the adapter amplifies the outage: task pile-up, memory creep over days on a long-running process, duplicate full-state floods to the server (each triggering automation re-evaluation and DB load), and stale states replayed as fresh after reconnect.

**Recommendation:** Debounce/coalesce update(homes:) (single in-flight updateEntities with a dirty flag or cancel-and-replace, 1-2s debounce over delegate bursts); bound the stream (.bufferingNewest(N) or newest-per-EntityId conflation); only yield items whose value actually changed since the last yield.

### 13. A HomeKit change notification is dropped entirely if the follow-up readValue() fails — real sensor edges lost

**Severity:** major · **Verified:** confirmed in main review against source
**Location:** `Sources/Adapter/Extensions/HMCharacteristic.swift:83-87 (path: Sources/Adapter/HomeKitAdapter+Delegates.swift:209-216)`

```swift
} catch {
    // this might occur when e.g. the IKEA hub or a device is not available
    homeKitLogger.warning("Error while getting characteristic data - ...")
    return nil
}
```

Found by 2 lenses (adapter-homekit, event-pipeline). accessory(_:service:didUpdateValueFor:) already carries the fresh value in characteristic.value — HomeKit updated it as part of delivering the notification — but getEntityStorageItem() unconditionally issues readValue(), a network round-trip to the accessory (plus extra saturation/brightness reads for hue). If that read throws (device momentarily busy/unreachable — the comment itself says this is expected), the whole item becomes nil and the delegate callback returns without yielding anything. No retry, no fallback to the already-updated cached value; the pushed edge will not be re-delivered.

**Impact:** The exact events HomeKit pushed (motion detected, contact opened) are intermittently lost during hub/Thread blips — missed automation triggers with only a warning log, and server state silently diverges until the opposite edge arrives. Also adds seconds of latency to every event.

**Recommendation:** On the delegate-update path, build the EntityStorageItem from the already-updated characteristic.value without calling readValue() (or fall back to the cached value / retry once when readValue() throws). Keep the active read only for the polling paths (getAllEntitiesLive/updateEntities).

### 14. Per-event unstructured delegate Tasks can deliver events out of order, leaving the server's entity cache holding a reverted state for up to 2 hours

**Severity:** major · **Verified:** confirmed in main review against source
**Location:** `Sources/Adapter/HomeKitAdapter+Delegates.swift:210-215`

```swift
Task {
    let item = await characteristic.getEntityStorageItem()
    ...
    self.entityStreamContinuation.yield(item)
}
```

(event-pipeline lens) Every didUpdateValueFor spawns an independent Task whose latency is dominated by a network readValue(). Two rapid changes to the same characteristic (motion true → false) can complete in reverse order: the older state (with the older embedded timestamp, HMCharacteristic.swift:40) is yielded LAST. The DB is timestamp-sorted so getCurrent stays correct, but HomeManager.addEntityHistory inserts into entityCache in ARRIVAL order with no timestamp comparison (HomeManager.swift:137-139), so the cache — which getCurrentEntity prefers over the DB — ends up holding the reverted value until the next event for that entity or the 2h TTL expiry.

**Impact:** Automations read a stale flipped state (e.g. motion=true long after it ended, or vice versa) for up to 2 hours; level-triggered automations then make wrong decisions on any subsequent event.

**Recommendation:** In addEntityHistory, only insert into entityCache when item.timestamp >= the cached item's timestamp. On the adapter, serialize per-characteristic reads (e.g. an AsyncStream per entity or a serial queue keyed by uniqueIdentifier).

### 15. Data race on HomeKitHomeManager.manager: mutated from a detached task, read from HomeKit delegate threads, hidden by @unchecked Sendable

**Severity:** major · **Verified:** confirmed in main review against source
**Location:** `Sources/Adapter/HomeKitAdapter+Delegates.swift:14, 36-46`

```swift
final class HomeKitHomeManager: NSObject, @unchecked Sendable {
    ...
    Task.detached(priority: .low) { [weak self] in
        for await _ in Timer.publish(every: .hours(6)) {
            ...
            self.manager = HMHomeManager()
            self.manager.delegate = self
```

(concurrency lens) `var manager: HMHomeManager` is unsynchronized mutable state in an @unchecked Sendable class. It is written every 6 hours from a detached task (arbitrary executor) and read concurrently from trigger(scene:) (line 54, called from the distributed command receiver), from checkAuthorization(), and from every HMHomeManagerDelegate/HMHomeDelegate/HMAccessoryDelegate callback (`update(homes: manager.homes)`), which HomeKit delivers on the main queue. No lock or actor isolation; @unchecked Sendable suppresses the compiler diagnosis. Besides torn-read UB risk, the two-step `self.manager = HMHomeManager()` / `self.manager.delegate = self` is not atomic: a delegate callback from the old manager can interleave and read the half-initialized new manager.

**Impact:** The exact class of long-running-process degradation this system suffers from: after days of 6h resets, a race can wire delegates to a dropped manager instance or crash the adapter — HomeKit events silently stop flowing until the next restart, with no alert.

**Recommendation:** Make HomeKitHomeManager an actor (or confine `manager` to @MainActor, which HomeKit expects anyway) and remove @unchecked Sendable; perform the reset on the same isolation as all readers.

### 16. APNS device tokens are deleted on ANY send error — a transient APNS/network outage unregisters every device

**Severity:** major · **Verified:** confirmed in main review against source
**Location:** `Sources/Server/Controllers/PushNotifcationService.swift:89-104`

```swift
} catch {
    Self.logger.warning("Failed to send push notification to \(deviceToken.deviceName)...")
    try await DeviceToken.query(on: database)
        .filter(\.$tokenString == deviceToken.tokenString)
        .delete()
```

(server-core lens) sendAlert (89-104), clearNotification (50-64), startOrUpdateLiveActivity (219-236) and endAllLiveActivities (276-293) all delete the device token from the database on ANY thrown error. APNSError distinguishes permanent token failures (.badDeviceToken, .unregistered/410) from transient ones (connection reset, timeout, 500/503 from APNS, JWT clock skew, DNS failure in the container). A brief APNS or egress-network outage while a notification is in flight deletes the tokens of every registered device in the loop.

**Impact:** One transient outage permanently disables the push channel — including CriticalLogNotifier alerts, window notifications, and Live Activities — for all devices, with no server-side recovery until each user next opens the iOS app. This is the alerting channel for every other failure, so it silently amputates observability.

**Recommendation:** Inspect the error: delete the token only for APNSError reasons that indicate an invalid/unregistered token (.badDeviceToken, .expiredToken, .unregistered / HTTP 410); for all other errors keep the token and just log (optionally retry with backoff).

### 17. getCurrent/getPrevious load an entity's ENTIRE history into memory on every state event, on a table with no secondary indexes

**Severity:** major · **Verified:** confirmed in main review against source
**Location:** `Sources/Server/Models/EntityStorageDbRepository.swift:23-38 (getPrevious: 40-60)`

```swift
.filter(\.$entityCharacteristicType == entityId.characteristicType.rawValue)
.sort(\.$timestamp, .descending)
.all()
.filter { item in ... }
.first
```

Found by 2 lenses (server-core, event-pipeline). getCurrent fetches ALL rows for the entity (.all()), hydrates them into models, then filters (the characteristicsName filter is applied post-fetch) and takes .first in memory; getPrevious does the same for two rows. getCurrent runs on EVERY incoming HomeKit state event via the dedupe check in HomeManager.addEntityHistory (HomeManager.swift:154-171) and on every automation cache miss. With 90-day retention (DatabaseCleanupJob.swift:15) and chatty characteristics (illuminance, CO2, brightness), a once-a-minute sensor accumulates ~130k rows — every new reading loads them all. On top of that, no migration creates ANY index on (entityPlaceId, entityServiceName, entityCharacteristicType, timestamp) — Migrations/01_CreateEntityStorageDbItem.swift creates only fields — so getCurrent, getHistory, and the cleanup delete are full table scans. Event bursts spawn unbounded concurrent detached persist tasks each doing this full fetch against a pool with a 10s timeout (configure.swift:109).

**Impact:** Classic long-running degradation: server memory and MySQL CPU/IO grow steadily toward the 90-day steady state; persistence tasks slow down and pile up; the /health SELECT competes with table scans and drifts toward its 5s timeout; pool-timeout 'Failed to persist entity item' criticals under bursts cause history gaps that corrupt getPrevious-based edge detection.

**Recommendation:** Add .limit(1)/.limit(2) and push the characteristicsName filter into SQL (nullable-aware) so getCurrent/getPrevious read O(1) rows; add a migration creating a composite index on (entityPlaceId, entityServiceName, entityCharacteristicType, timestamp) plus an index on timestamp for the cleanup delete.

**Verifier corrections/refinements:**
- Verified: retention is 90 days (`DatabaseCleanupJob.retentionDays`), and a grep over `Sources/Server/Migrations/` finds no index/unique constraint in any migration — all lookups run over an unindexed, ever-growing table.

### 18. Automation activate/deactivate toggles are never persisted — lost on every server restart

**Severity:** major · **Verified:** confirmed in main review against source
**Location:** `Sources/Server/Controllers/HomeAutomationConfigService.swift:31-40`

```swift
func setAutomationActive(with name: String, to value: Bool) {
    let automations = self.automations.map { ... }
    self.automations = automations
}
```

(server-core lens) set(location:automations:) persists via try save(), but setAutomationActive — the path behind the OpenAPI activate/deactivate endpoints used by the iOS Controller (OpenAPIController.swift:36,46) — mutates only in-memory state and never calls save(). The change survives only until the next restart (or is coincidentally captured if a full POST /config happens later, since that merges the in-memory isActive).

**Impact:** After any server restart (deploy, crash, DB-outage crash-loop), automations a user explicitly disabled silently re-arm (e.g. lights/valves start switching again), and automations a user enabled are silently off. No alert; the user only finds out from device behavior.

**Recommendation:** Call try? save() (with error logging) at the end of setAutomationActive, or persist isActive flags separately (DB table) and overlay them in loadOrDefault().

**Verifier corrections/refinements:**
- Verified: `OpenAPIController.swift:36/46` call `setAutomationActive(with:to:)`, which mutates only in-memory state; `save()` is only invoked from the full `set(location:automations:)` path.

### 19. In-flight automation state (on → sleep → off, pending notifications, open-window tracking) is memory-only — a server restart mid-sequence leaves devices on and Live Activities orphaned

**Severity:** major · **Verified:** confirmed in main review against source
**Location:** `Sources/HAImplementations/Automations/TurnOnForDuration.swift:30-41 (also Sources/HAApplicationLayer/Managers/WindowManager.swift:15)`

```swift
for device in switches { await device.turnOn(with: hm) }
try await Task.sleep(for: duration)
for device in switches { await device.turnOff(with: hm) }
```

Found by 3 lenses (remote-calls, event-pipeline, server-core). TurnOnForDuration, MotionAtNight (noMotionWait/dimWait sleeps), and WindowOpen (15-minute notification wait) hold their pending compensating step purely in a task's stack via Task.sleep. Nothing is persisted and there is no startup reconciliation. A server restart mid-sequence — deploy, crash, the user's own scheduled RestartSystem automation which calls exit(1) (RestartSystem.swift:28), or a wedge-recovery restart — discards the pending off-step/notification. Likewise WindowManager.windowStateIsOpen is an in-memory dictionary: after a restart, windows that were open produce no overdue reminders, previously delivered notifications are not cleared, and running Live Activities are never updated/ended until the next contact-sensor change; there is no rebuild from the adapter (no full-state replay on reconnect) or from the DB (where contact states ARE persisted).

**Impact:** A switch/pump/heater turned on for a fixed duration stays ON indefinitely if the server restarts during the interval (for a daily trigger: up to ~24h). Open-window notifications and Live Activities silently desync after every deploy. No error is logged and no alert fires, because nothing failed from the code's perspective.

**Recommendation:** Persist pending compensating actions (entityId + action + due date) in the DB and execute overdue ones at startup — or make these automations idempotent against the every-minute .time event ('is a deadline past due?' instead of sleeping through it). Rebuild WindowManager state at boot from the latest persisted isContactOpen values (EntityStorageDbRepository.getCurrent) or a one-shot getAllEntitiesLive() once the adapter connects.

### 20. Full-state replays re-trigger automations with no dedup before triggering — WindowOpen's notification timer is reset by every replay, and in-flight executions are cancelled

**Severity:** major · **Verified:** confirmed in main review against source
**Location:** `Sources/Server/Jobs/EventProcessingJob.swift:22-32`

```swift
for await event in homeEventsStream {
    if case .change(let item) = event { await homeManager.addEntityHistory(item) }
    await automationService.trigger(with: event)
}
```

(event-pipeline lens) updateEntities() re-yields the state of EVERY subscribed characteristic on every home/accessory delegate callback — including accessoryDidUpdateReachability, which fires per accessory during hub churn (HomeKitAdapter+Delegates.swift:110-127, 196-199). addEntityHistory dedups only the DB write; automationService.trigger(with:) runs unconditionally for every event, including unchanged replays. Automations are level-triggered (e.g. WindowOpen.shouldTrigger returns true for any change event of its sensor, WindowOpen.swift:27-33), and AutomationService.set(task:) cancels the previous run for the same name (AutomationService.swift:71-78). So a replayed unchanged 'window open' state cancels the sleeping WindowOpen task mid-countdown and restarts execute() with a fresh `let opened = Date()` (WindowOpen.swift:47-49), re-arming the 15-minute timer and rewriting WindowOpenState/Live Activities with a fresh opened date.

**Impact:** Under periodic delegate churn (reachability flaps, the 6h reset, any accessory added/renamed) the 'window left open' notification can be postponed indefinitely, and any long-running automation sequence (MotionAtNight dim/off) is cancelled and restarted by state echoes that changed nothing.

**Recommendation:** Deduplicate before triggering: in HomeEventProcessingJob (or addEntityHistory), compare the incoming item against the cached current value and skip automationService.trigger for unchanged replays (or give Automatable an explicit edge-vs-level contract). For WindowOpen specifically, derive 'opened' from the persisted history transition instead of Date() at execute time.

**Verifier corrections/refinements:**
- Verified against `WindowOpen.swift`: `shouldTrigger` returns true for ANY change event of its contact sensor (no old/new comparison), and `execute()` restarts the wait with a fresh `opened = Date()` — so full-state replays genuinely reset the 15-minute notification timer, and `AutomationService.set(task:)` cancels the in-flight wait.

### 21. Automations keep acting on frozen data while the adapter is disconnected — no staleness marking and no gating on connection status

**Severity:** major · **Verified:** confirmed in main review against source
**Location:** `Sources/HAApplicationLayer/HomeManager.swift:56-61`

```swift
public func getCurrentEntity(with entityId: EntityId) async throws -> EntityStorageItem {
    if let item = await entityCache.value(forKey: entityId) { return item }
    return try await storageRepo.getCurrent(entityId).get(with: log)
}
```

(event-pipeline lens) Entity reads serve from a 2-hour in-memory cache (line 23) and then fall back to the last row ever persisted — with no timestamp/staleness check and no awareness of the cluster connection status. Nothing on the server consults customActorSystem.latestConnectionStatus outside of /health (routes.swift:34-38). Time-driven events from ClockJob keep flowing every minute, so time-triggered automations (Turn, TurnOnForDuration, EnergyLowPrice, GardenWatering) and level-triggered ones keep evaluating shouldTrigger against data that may be hours or days old while the adapter is down.

**Impact:** During an adapter outage the server makes decisions on a frozen world model (e.g. 'window closed' from before the outage) and issues commands that then fail-and-vanish (see retry finding), all without any signal that the data is stale.

**Recommendation:** Propagate staleness: expose the item timestamp plus connection status via HomeManagable and have automations (or a central guard in AutomationService.trigger) skip or degrade when the adapter has been disconnected longer than a threshold; at minimum stop evaluating entity-state-dependent automations while status != .up and log/alert once.

### 22. Adapter-down is invisible to alerting: heartbeat logs only .warning (no push), and the dead-man HealthCheck ping keeps firing regardless of adapter connectivity

**Severity:** major · **Verified:** confirmed in main review against source
**Location:** `Sources/HAImplementations/Automations/HealthCheck.swift:25-31 (heartbeat: Sources/SharedDistributedCluster/CustomActorSystem.swift:339-346)`

```swift
guard case HomeEvent.time(_) = event else {
    return false
}
return true
```

Found by 2 lenses (event-pipeline, server-core). The server pushes APNS alerts only for .critical log events (CriticalNotifyingLogHandler, CriticalLogNotifier.swift:79-84, wired in entrypoint.swift:13-19), but when the adapter connection is down the only server-side signal is the 'Cluster heartbeat (not up)' log at .warning level — no critical, hence no push. Meanwhile the HealthCheck automation, which exists to feed an external dead-man monitor (e.g. healthchecks.io), triggers on every .time event unconditionally; those events come from the server-local ClockJob, not from the adapter, so the ping continues every minute during the known cluster wedge or any adapter outage even though no entity events flow and device automations are effectively dead. The only red signal is /health returning 503, which only Docker sees and Docker does not act on unhealthy.

**Impact:** A dead adapter (or a wedged cluster) produces zero alerts on every channel: external monitoring stays green, no push fires, automations silently stop reacting to the house — exactly the 'silent stop of automations' failure mode from the incident history, delaying human response.

**Recommendation:** Escalate the server heartbeat to .critical (or send a push directly) after N consecutive not-up minutes, and gate HealthCheck.execute on system health — skip the ping (letting the dead-man monitor fire) when customActorSystem.latestConnectionStatus != .up or when the last adapter entity event is older than a threshold.

## Minor (18)

### 23. Timer.publish producer task ignores cancellation, never terminates, bursts stale ticks after host sleep, and delays the first tick to the next minute boundary regardless of the requested period

**Severity:** minor · **Verified:** confirmed in main review against source
**Location:** `Sources/Shared/Timer.swift:16-31`

```swift
Task {
    var nextEventDate = Calendar.current.nextDate(after: Date(), matching: DateComponents(second: 0), ...)!
    while true {
        try? await Task.sleep(for: .seconds(nextEventDate.timeIntervalSinceNow))
        continuation.yield(nextEventDate)
```

Found by all 6 lenses. The unstructured producer Task has several defects: (1) `while true` with `try? await Task.sleep` swallows CancellationError and never checks Task.isCancelled, and the continuation is never finished (no onTermination) — every publish() call leaks a perpetual task even after its consumer is gone (one per HomeKitAdapter re-init; ClockJob, DatabaseCleanupJob, and the HomeManager retry loop all rely on it), and if the task ever runs in a cancelled context the loop busy-spins at 100% CPU yielding into a dead continuation. (2) The first tick always aligns to the next second==0 minute boundary regardless of `duration` — so HomeManager's 'every 5 seconds' failed-action retry loop (HomeManager.swift:45) starts up to 60s late, and the 6h HMHomeManager reset fires ~60s after every app start. (3) After host sleep or a clock jump, nextEventDate is in the past and negative sleep intervals produce a rapid catch-up burst of stale yields — ClockJob replays stale .time events into the automation stream (Time.isEqual matches hour/minute, so a 'run at 03:00' automation can fire at wake-up). Also: the `Calendar.current.nextDate(...)!` force-unwrap, and the 6h-reset consumer's `guard let self else { continue }` (HomeKitAdapter+Delegates.swift:38) keeps ITS loop alive forever after the owner deallocates.

**Impact:** Leaked producer tasks accumulate per re-init on the long-running adapter; the failed-action retry window is up to 60s later than intended; time-based automations receive catch-up bursts of stale events after machine sleep; latent 100%-CPU spin if any owner starts cancelling scoped work.

**Recommendation:** Loop on `while !Task.isCancelled`, use plain `try await Task.sleep` and break on CancellationError, finish the continuation and cancel the internal task via continuation.onTermination, schedule the first tick at now + duration instead of the minute boundary, and clamp/skip ticks that have fallen behind (recompute from Date()). Change the consumer's `continue` to `return`.

**Verifier corrections/refinements:**
- Additional observation from the main review: the 6-hour reset loop in `HomeKitAdapter+Delegates.swift:38` uses `guard let self else { continue }` — after the manager is gone the subscription keeps ticking forever instead of exiting (`return`). The busy-spin scenario is theoretical (these producer tasks are never cancelled in practice); the per-`publish()` task leak and the minute-aligned first tick are real.

### 24. Server homeEvents AsyncStream is unbounded — backlog grows without limit when automation evaluation stalls on the DB, then replays stale events

**Severity:** minor · **Verified:** confirmed in main review against source
**Location:** `Sources/Server/AppStorage.swift:16`

```swift
private let homeEvents = AsyncStream.makeStream(of: HomeEvent.self)
```

Found by 3 lenses. makeStream uses the default .unbounded policy. Producers are ClockJob (one event per minute) and HomeEventReceiver.process (adapter events, no backpressure across the distributed boundary); the single consumer, HomeEventProcessingJob, awaits addEntityHistory + automationService.trigger per event, and shouldTrigger implementations hit MySQL via getCurrentEntity on cache misses (10s connectionPoolTimeout each). During a DB outage — especially with a cold cache after a restart — each event can block ~10s per automation wave, so events accumulate without bound and are replayed stale after recovery (e.g. hours-old motion events and time-matched automations like RestartSystem firing for long-past minutes).

**Impact:** Memory growth during a stall, then a burst of stale automation triggers (lights reacting to old motion, time automations firing late) once the loop unblocks; history for the outage window is separately lost.

**Recommendation:** Create the stream with a bounded policy (e.g. .bufferingNewest(N)), and/or drop .time events older than roughly one interval and coalesce .change events per EntityId at dequeue; skip automation triggering for events older than a staleness threshold.

### 25. Per-event detached persistence tasks are unbounded, unordered, and race the dedupe check during DB slowness

**Severity:** minor · **Verified:** confirmed in main review against source
**Location:** `Sources/HAApplicationLayer/HomeManager.swift:154-171`

```swift
Task.detached(priority: .background) {
    do {
        if var currentItem = try await self.storageRepo.getCurrent(item.entityId) {
```

Found by 2 lenses (server-core, remote-calls). addEntityHistory spawns a new detached Task per incoming event doing a read-check-write (getCurrent → compare → add) with no per-entity serialization. When MySQL is slow or down, each task blocks up to the 10s connection-pool timeout, so tasks (each holding an EntityStorageItem) accumulate proportionally to event rate × outage duration, competing for pool connections with API requests and the /health probe. Concurrent tasks for the same entity race the dedupe (two rapid changes both compare against the same 'current' — duplicate or out-of-order rows), and completion order is not event order. Failures are only logged (.critical, push-throttled 1/label/hour) and the items are permanently dropped from history.

**Impact:** During a DB outage or slowdown with an event storm: task/memory buildup, pool exhaustion degrading the whole server, a critical-log/push storm, silent history gaps for the outage window, and scrambled/duplicated history that corrupts getPrevious-based logic.

**Recommendation:** Funnel persistence through a single serial consumer (actor or bounded AsyncStream, preserving per-entity ordering) instead of one detached task per event; optionally keep a small bounded in-memory queue to replay writes after the DB recovers, and rate-limit the critical log during sustained failure.

### 26. Startup race: adapter joins the cluster before HomeKitCommandReceiver is checked in with the receptionist

**Severity:** minor · **Verified:** confirmed in main review against source
**Location:** `Apps/FlowKitAdapter/FlowKitAdapterApp.swift:97-111`

```swift
let system = await CustomActorSystem(...)  // init starts tryReconnectIfNeededInBackground()
...
commandReceiver = await system.makeLocalActor(actorId: .homeKitCommandReceiver) { ... }
_ = await system.checkIn(actorId: .homeKitCommandReceiver, commandReceiver)
```

(cluster-lifecycle lens) CustomActorSystem.init (CustomActorSystem.swift:133-135) immediately starts the reconnect loop, which can complete the join before the app reaches checkIn. In that window the server's HomeManager.getAdapter lookup returns nil: perform failures land in the failedActions retry loop (recovers, modulo the dead-retry bug), but getAllEntitiesLive() and trigger(scene:) throw/fail without retry. Similarly, right after an adapter restart the server's receptionist may briefly still hold the OLD dead receiver until the downing evicts it.

**Impact:** Scene triggers and live-entity queries issued in the seconds around an adapter (re)start fail spuriously; POST /config validation can fail transiently.

**Recommendation:** Check in the HomeKitCommandReceiver before the system starts joining (pass a registration closure to CustomActorSystem.init, or delay tryReconnectIfNeededInBackground until after first checkIn).

### 27. Server resolves the adapter via receptionist lookup().first with no liveness or incarnation preference

**Severity:** minor · **Verified:** confirmed in main review against source
**Location:** `Sources/SharedDistributedCluster/CustomActorSystem.swift:436-438`

```swift
public func lookup<Guest>(_ key: DistributedReception.Key<Guest>) async -> Guest? ... {
    return await actorSystem.receptionist.lookup(key).first
}
```

(remote-calls lens) Every command resolves the HomeKitCommandReceiver as `.first` of the receptionist listing (wired in Sources/Server/configure.swift:221-223). Receptionist entries are only evicted when their node reaches .down — precisely the transition the SWIM/wedge issue prevents — so after an adapter restart the listing can contain both the dead incarnation and the fresh one, and `.first` has no defined preference. Each call routed to the dead incarnation burns the full 15s remote-call timeout before HomeManager records a failure.

**Impact:** After adapter restarts (especially during a partially-wedged membership), commands can repeatedly target a dead actor, adding 15s latency + failure per action; combined with the defeated retry (see ActionLogManager finding) those commands are then lost.

**Recommendation:** Prefer guests whose node is .up (filter the listing via cluster.membershipSnapshot) or maintain a current receiver from a listing(of:) subscription replaced on membershipChange, mirroring what the adapter does for HomeEventReceiver.

### 28. Mutable 'receiver' var shared by two unstructured tasks — safe only via implicit MainActor inheritance; listing-stream death is unlogged

**Severity:** minor · **Verified:** confirmed in main review against source
**Location:** `Apps/FlowKitAdapter/FlowKitAdapterApp.swift:123-129`

```swift
var receiver: HomeEventReceiver?
Task {
    for await foundReceiver in await system.listing(of: .homeEventReceiver) {
        receiver = foundReceiver
    }
}
```

(event-pipeline lens) The listing task writes 'receiver' while the entity loop reads it. Both tasks currently inherit the MainActor from the SwiftUI context, which is what makes this safe today — but that safety is implicit and fragile: moving the loop off the MainActor (e.g. to fix UI stalls) silently introduces a data race on the single path all events flow through. Also, if the listing stream ever terminates (receptionist error), nothing logs that discovery died. (Distinct from the stale-receiver/leak finding above: this is about the concurrency-safety of the shared variable itself.)

**Impact:** Fragile correctness on the event hot path; a future refactor detaching these tasks introduces a real data race on the receiver reference.

**Recommendation:** Hold the receiver in a small actor (or @MainActor-annotated box) with an explicit setter from the listing task, and log + restart the listing loop if it finishes.

### 29. AsyncCurrentValuePublisher.get() ignores cancellation and has no timeout — remote calls into the adapter can hang suspended forever and leak continuations

**Severity:** minor · **Verified:** confirmed in main review against source
**Location:** `Sources/Adapter/AsyncCurrentValuePublisher.swift:24-34`

```swift
return await withCheckedContinuation { (continuation: CheckedContinuation<Value, Never>) in
    continuations.append(continuation)
}
```

Found by 2 lenses (adapter-homekit, concurrency). If no value was ever sent (HomeKit auth denied, homed never responds), getHomes() suspends indefinitely — including every distributed perform/getAllEntitiesLive call from the server. withCheckedContinuation never resumes on task cancellation, so even after the server-side 15s remote-call timeout the adapter-side task remains suspended and the continuation entry leaks in the `continuations` array until the next send (which may never come); cancelled waiters are never removed either.

**Impact:** During a HomeKit outage the adapter accrues suspended tasks/continuations for every incoming command, and callers observe indistinguishable 15s timeouts instead of a fast 'HomeKit unavailable' error; on a long-running degraded adapter these accumulate.

**Recommendation:** Use withTaskCancellationHandler so waiters honor cancellation and are removed from `continuations`, and/or give get() a deadline that throws a descriptive error so callers fail fast instead of hanging.

### 30. getAllEntitiesLive can exceed the 15s distributed-call timeout

**Severity:** minor · **Verified:** confirmed in main review against source
**Location:** `Sources/Adapter/DistributedActors/HomeKitCommandReceiver.swift:34-41 (timeout: Sources/SharedDistributedCluster/CustomActorSystem.swift:173)`

```swift
public distributed func getAllEntitiesLive() async -> [EntityStorageItem] {
    ...
    let entities = await adapter.getAllEntitiesLive()
```

(adapter-homekit lens) settings.remoteCall.defaultTimeout = .seconds(15), but HomeKitAdapter.getAllEntitiesLive() performs a live readValue() round-trip for every readable characteristic in the home at .low task priority — the code itself warns 'this call might take a while'. On a large home or sluggish hub the server-side call times out while the adapter keeps working, and the server route/automation sees a spurious failure.

**Impact:** Intermittent failures of the /entities route and UpsertScene automation on slow HomeKit days, with wasted duplicate work on retries.

**Recommendation:** Return cached last-known values (the adapter already receives notifications) or raise the per-call timeout for this specific remote call; alternatively page the query.

### 31. Private-API KVC back-pointers (value(forKey:)) for home/characteristic can silently break on OS updates

**Severity:** minor · **Verified:** confirmed in main review against source
**Location:** `Sources/Adapter/Extensions/HomeKit-Extensions.swift:13-29`

```swift
extension HMAccessory {
    var home: HMHome? {
        value(forKey: "home") as? HMHome
    }
}
```

(adapter-homekit lens) HMAction.characteristic, HMAccessory.home and HMActionSet.home are read via KVC on undocumented keys. An OS update that renames the ivar makes these return nil (or raise for non-KVC-compliant keys). HMAccessory.home == nil sends addEntityToScene down a silent assertionFailure(); return path in release.

**Impact:** After an OS update, scene management can silently stop working with no error surfaced to the server.

**Recommendation:** Resolve the owning home by searching manager.homes for the accessory/actionSet (public API) instead of KVC; at minimum throw instead of returning silently when nil.

### 32. HomeKit authorization loss is only logged — adapter keeps reporting healthy with zero entities

**Severity:** minor · **Verified:** confirmed in main review against source
**Location:** `Sources/Adapter/HomeKitAdapter+Delegates.swift:148-152`

```swift
private func checkAuthorization() {
    if manager.authorizationStatus != .authorized {
        log.critical("homeManager.authorizationStatus - not authorized")
    }
}
```

(adapter-homekit lens) If HomeKit authorization is missing or revoked, the only reaction is a critical log line. Homes come back empty, getAllEntitiesLive() returns [], subscriptions are never established — yet the cluster connection stays .up, so neither the adapter UI nor the server can distinguish 'healthy but no devices' from 'unauthorized'. No re-prompt/recovery path exists.

**Impact:** A permissions reset (TCC reset, OS migration) turns the adapter into a silent zombie: automations receive no events while the server's /health endpoint stays green.

**Recommendation:** Surface authorization state in the adapter's status (e.g. a dedicated ConnectionStatus/health field forwarded to the server), and have findEntity/getAllEntitiesLive fail loudly when authorizationStatus != .authorized.

### 33. Sunrise/sunset events fire only on exact-minute match — a missed tick silently skips the event for the whole day

**Severity:** minor · **Verified:** confirmed in main review against source
**Location:** `Sources/Server/Jobs/ClockJob.swift:24-28`

```swift
if Sun.sunriseElevation(for: date, ...) == .horizon {
    homeEventsContinuation.yield(.sunrise)
} else if Sun.sunsetElevation(for: date, ...) == .horizon {
```

(server-core lens) Sun.sunriseElevation returns .horizon only when the tick date equals the sunrise minute at .minute granularity (Sources/HAModels/Helper/Sun.swift:71-75). The minute tick can be missed: the Timer stream buffers only the newest tick (.bufferingNewest(1), Sources/Shared/Timer.swift:14), and a server restart or DB-outage crash-loop spanning that minute skips it entirely. There is no catch-up or edge-detection (below→above transition), so the day's sunrise/sunset event is simply never emitted.

**Impact:** Sunset/sunrise-triggered automations (lights, scenes) silently do not run for that day if the server was restarting or stalled during the one matching minute.

**Recommendation:** Track the last processed tick and detect the below→above (or above→below) transition between consecutive ticks instead of requiring exact-minute equality, so a late tick still fires the event once.

### 34. Release-build APNS configuration force-unwraps environment variables — opaque crash-loop on misconfiguration

**Severity:** minor · **Verified:** confirmed in main review against source
**Location:** `Sources/Server/configure.swift:167-169`

```swift
let notificationPrivateKey = String.fromBase64(Environment.get("PUSH_NOTIFICATION_PRIVATE_KEY_BASE64")!)!
let notificationKeyIdentifier = Environment.get("PUSH_NOTIFICATION_KEY_IDENTIFIER")!
let notificationTeamIdentifier = Environment.get("PUSH_NOTIFICATION_TEAM_IDENTIFIER")!
```

(server-core lens) In release builds a missing or non-UTF8/invalid-base64 push env var traps with a bare force-unwrap crash (unlike AUTH_TOKEN, which gets an explanatory fatalError at lines 61-66). Under restart:unless-stopped the container crash-loops with only a backtrace to explain why.

**Impact:** A single missing env var after an ops change turns into an infinite crash-loop whose cause must be reverse-engineered from a swift-backtrace dump; the whole home automation stays down meanwhile.

**Recommendation:** Replace the force-unwraps with guard-let + fatalError messages naming the missing/invalid variable, mirroring the AUTH_TOKEN pattern.

### 35. CriticalLogNotifier consumes its hourly throttle slot even when the notification send fails

**Severity:** minor · **Verified:** confirmed in main review against source
**Location:** `Sources/Server/CriticalLogNotifier.swift:36-46`

```swift
lastNotificationTime[label] = now

do {
    try await sender.sendNotification(...)
} catch {
    // Avoid recursion: do not log at .critical here
}
```

(server-core lens) The throttle timestamp is recorded before sending. If the send fails — which is likely exactly when things are broken, since PushNotifcationService must first read device tokens from MySQL — the failure is swallowed and the label is muted for a full hour. Critical events caused BY a DB outage therefore can never produce an alert (token lookup fails), and even after the DB recovers seconds later the alert stays suppressed.

**Impact:** The primary alerting path is blind during the failures it most needs to report; recovery of the alert is delayed up to an hour.

**Recommendation:** Only record lastNotificationTime after a successful send (or clear it in the catch block), and consider an alerting path that does not depend on the DB (cache device tokens in memory after first load).

### 36. Startup has no in-process wait/retry for the database — relies entirely on container restart policy

**Severity:** minor · **Verified:** confirmed in main review against source
**Location:** `Sources/Server/configure.swift:117`

```swift
try await app.autoMigrate()
```

(server-core lens) If MySQL is not yet accepting connections (docker-compose brings app and db up concurrently), autoMigrate throws after the 10s pool timeout, configure() rethrows, and entrypoint.swift:31-37 shuts down and exits non-zero. Recovery depends entirely on the compose restart policy in the external config repo; with restart: unless-stopped this becomes a crash-loop until the DB is ready, and with no restart policy the server stays dead after a host reboot where the DB comes up slowly.

**Impact:** Fragile cold-start ordering: any deployment without the right restart policy (or a long MySQL crash-recovery) leaves the server down without self-healing.

**Recommendation:** Wrap autoMigrate in a bounded retry loop (e.g. retry every 5s for up to 2 minutes, logging each attempt) before failing hard, and/or document a depends_on: condition: service_healthy requirement for the compose file.

### 37. Membership apply errors silently swallowed in the connection-status event loop

**Severity:** minor · **Verified:** confirmed in main review against source
**Location:** `Sources/SharedDistributedCluster/CustomActorSystem.swift:232`

```swift
_ = try? membership.apply(event: event)
```

(concurrency lens) The locally-folded `membership` is the sole input to peerStatus, isLocalNodeDown, and therefore the grace timer, /health, and the adapter's restart decisions. If apply ever throws (out-of-order event, unexpected snapshot), the failure is discarded and the local view silently diverges from the real cluster state — the exact class of 'status says joining forever / up while actually down' symptom this subsystem exists to detect. Given the incident history, a divergence here would be invisible.

**Impact:** Wrong connection status with zero trace: /health can 503 while healthy or report up while wedged, and the recovery logic keyed off this state misbehaves undetectably.

**Recommendation:** Log at .warning with the failing event when apply throws, and re-seed from actorSystem.cluster.membershipSnapshot on the next event (or periodically in the heartbeat) so the folded view self-corrects.

### 38. AutomationService task replacement is cooperative-only: superseded automation can keep issuing commands alongside its replacement

**Severity:** minor · **Verified:** confirmed in main review against source
**Location:** `Sources/HAApplicationLayer/AutomationService.swift:71-78`

```swift
if let runningTask = runningTasks[id], !runningTask.isCancelled {
    runningTask.cancel()
}
runningTasks[id] = task
```

(concurrency lens) The new execute() Task is created and started (line 34) before `set` cancels the old one, and cancel only takes effect at the old task's next cancellation check — automations awaiting homeManager.perform (distributed call, up to 15s) or long sleeps do not stop immediately, and the perform itself is not cancellation-aware. Two instances of the same automation can therefore overlap and issue contradictory commands (e.g. old run's delayed turnOff after new run's turnOn), which then also poisons the command cache/drift logic.

**Impact:** Occasional contradictory device commands after rapid re-triggering (motion re-fires during a running MotionAtNight), surfacing as lights flickering off or automations 'fighting' — hard to diagnose, no error logged.

**Recommendation:** Await a cancellation acknowledgement before starting the replacement (oldTask.cancel(); await oldTask.value — it's Task<Void, Never> — then start the new one), and add try Task.checkCancellation() before each command in long automations.

### 39. Automation execute() failures are logged and dropped — no automation-level retry or compensation for partial multi-device state

**Severity:** minor · **Verified:** confirmed in main review against source
**Location:** `Sources/HAApplicationLayer/AutomationService.swift:36-41`

```swift
try await automation.execute(using: self.homeManager)
} catch is CancellationError {
} catch {
    self.log.error("Automation failed with error - \(error)")
}
```

(remote-calls lens) When execute() throws mid-way (e.g. getCurrentEntity DB error, isContactOpen remote failure), the automation aborts with only an error log: devices already commanded stay in their new state, the remainder never runs, and nothing re-triggers the automation. Combined with hm.perform() swallowing errors internally, a multi-light sequence like MotionAtNight can end with some lights adjusted and the turn-off phase never reached.

**Impact:** Partial device state after transient DB/adapter errors, with recovery dependent on the next natural trigger event; no alerting beyond a log line.

**Recommendation:** For automations with a terminal 'safe' phase (turn off), run that phase in a defer-like cleanup on error/cancellation where semantically safe, or re-enqueue the triggering event once after a delay.

### 40. Per-log-line unstructured Task in FileLogHandler: out-of-order log records and fatalError on rotation failure

**Severity:** minor · **Verified:** confirmed in main review against source
**Location:** `Sources/Shared/FileLogHandler.swift:119-121, 47-59`

```swift
Task {
    await stream.write(jsonLine)
}
```

(concurrency lens) Each log call spawns an independent Task hopping to the FileHandlerOutputStream actor, so file-log lines can be written out of chronological order (actor mailbox order across independent tasks is not FIFO with respect to spawn order) and a log storm spawns unbounded tasks. Separately, getNewFileHandle calls fatalError if file creation/opening fails — at midnight rotation with a full disk or permission hiccup this kills the adapter process. The adapter's file log is the primary forensic tool for the cluster-wedge investigations, so ordering matters.

**Impact:** Scrambled timestamps in the exact logs used to diagnose connection incidents; adapter crash loop on disk-full at rotation time.

**Recommendation:** Replace per-line Tasks with an AsyncStream consumed by one writer task (preserves order, bounds memory), and degrade gracefully (drop file logging, log to stderr) instead of fatalError when the log file cannot be opened.


---

## Suggested remediation order

1. **Close the wedge (Finding 1).** Implement the two deferred plan steps in `CustomActorSystem` for both roles: a SWIM-independent stuck-non-up watchdog (force `down()` of non-self members after N minutes below `.up`, targeting stale same-endpoint/different-UID incarnations), plus a gated server self-exit so `restart: unless-stopped` produces a fresh UID; drop the `everConnected` gate on the adapter grace timer (scale the grace period instead).
2. **Make the event/command path lossless across disconnects.** Buffer adapter events while the receiver is unavailable and re-push a full snapshot on every reconnect (`connectionStatus == .up` transition), not only on process restart; propagate `perform()` resolution failures back to the server; mark commands as executed only after success (fixes the retry no-op).
3. **Alerting.** Push a notification on sustained not-up (server side), gate `HealthCheck` on adapter connectivity so the external dead-man monitor actually detects adapter loss, record the `CriticalLogNotifier` throttle slot only after a successful send, and configure the notifier before the config is loaded.
4. **Restart durability.** Persist automation toggles (call `save()` in `setAutomationActive`, or move config into MySQL), document/harden the config-volume contract, and add startup reconciliation for window states and pending compensating actions.
5. **Hygiene (batchable).** Timer.publish cancellation + first-tick fix; bound the event streams; add DB indexes + `LIMIT 1` queries; discriminate APNS errors before deleting tokens; replace release-reachable `fatalError`/`assertionFailure` paths with logged degradation.

## Positive observations (resilience patterns already in place)

- Split-brain-proof leader topology — only the server can become leader, adapter uses `.none`, `onDownAction = .none`; deliberate and unit-tested (`CustomActorSystem.swift:154-176`, `ClusterLeadershipTests`).
- `/health` races DB + cluster checks against a hard 5s timeout and returns enriched `connectionDiagnostics()` in the 503 body (`routes.swift:22-52`).
- All distributed calls have a 15s default timeout — no remote call can hang forever (`CustomActorSystem.swift:173`).
- Adapter self-recovery ladder: onDown grace timer → `exit(1)` + launchctl KeepAlive; own-eviction detection both event- and poll-based; proactive downing of dead server incarnations before rejoin (`CustomActorSystem.swift:273-296, 350-396`).
- Wedge observability from PR #183: startup provenance, cluster-event logs, per-minute not-up heartbeat warnings.
- Command-drift invalidation from PR #184 is carefully designed (echo-aware, nil-safe, tolerances above rounding granularity).
- Write-then-verify on HomeKit write errors (`HomeKitAdapter.swift:155-168`); per-characteristic error containment in snapshot reads; deliberate HomeKit subscription budget.
- Server re-resolves the adapter actor per call via the receptionist instead of caching a remote reference (`configure.swift:221-223`).
- CRITICAL log events trigger APNS pushes (`CriticalNotifyingLogHandler`); fail-fast boot pairs with the Docker restart policy; serial event processing preserves ordering while long automations run detached; per-iteration error containment in cleanup/automation loops; secure-by-default auth.

---

## Coverage notes

- **Not in scope / not reviewed:** the Controller iOS app (`Sources/Controller`, `Apps/FlowKitController`), `ServerClient`, `HomeCLI`, and the Tibber integration — the review targeted the adapter, the server, and the connection layer between them.
- **Test-coverage gap on the connection layer:** `Tests/SharedDistributedClusterTests` covers the pure decision functions (`decide`, `isLocalNodeDown`) and real-cluster leadership (self-election, promote-then-down). Untested: the wedge scenario itself (a reachable stale `.joining` member blocking convergence), the `everConnected`-gated grace timer, the reconnect loop's stale-member eviction filter, restart-order sequences (adapter-first vs. server-first), and the adapter event pump across disconnects. A regression test for the wedge would make Finding 1's fix verifiable.

---

*Method note: review executed as a multi-agent workflow (6 finder lenses → dedup → 3-lens adversarial verification per finding), with the remainder of the verification and the completeness check completed manually against source after the automated verifiers hit session limits. Intermediate state was tracked in `temp.md`, which this file supersedes.*
