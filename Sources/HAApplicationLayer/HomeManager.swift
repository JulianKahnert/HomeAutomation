//
//  HomeManager.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 01.07.24.
//

import Foundation
import HAModels
import Logging
import Shared

@HomeManagerActor
public final class HomeManager: HomeManagable {
    /// Number of times a command is sent to the adapter before it is dropped.
    nonisolated private static let maxAttempts = 3

    private let log: Logger
    private let commandCache: CommandCache
    private let journal: Journal

    private let getAdapter: () async -> (any EntityAdapterable)?
    private let location: Location
    private let storageRepo: StorageRepository
    private let deliveries: DeliveryQueue
    private let storageUpkeep: (any StorageUpkeep)?
    /// Hands a changed, already checked server-owned state to the event stream (`report`).
    private let onReportedChange: @Sendable (EntityStorageItem) -> Void
    /// The last command that reached each radiator, keyed by room and radiator name; loaded from the journal at
    /// start and kept current by `perform`, so a decision never reads the database.
    private var lastCommands: [String: HeatingWrite] = [:]
    /// The changes of every entity of the last `readingRetention`, newest first; what a decision compares
    /// (the rise `FireplaceReminder` looks for). Fills from the changes since the start.
    private var recentReadings: [EntityId: [EntityStorageItem]] = [:]
    nonisolated private static let readingRetention: TimeInterval = 3 * 3600
    nonisolated private static let readingLimit = 500
    /// The current state of every entity, loaded from the database at start and then the last change, never a
    /// replay. No expiry and no eviction, so a replay is no change however long ago the last change was.
    private var currentStates: [EntityId: EntityStorageItem] = [:]
    /// The entities a source reported in this process; a state merely loaded from the database does not
    /// prove the entity still exists in HomeKit.
    private var reportedEntities: Set<EntityId> = []
    /// When each source (the origin of a report) last reported, a replay included. Memory only: empty after a
    /// restart until the first report, so a silent source differs from an unchanged one.
    private var lastReportBySource: [Origin: Date] = [:]
    /// One retry slot per entity: a newer failed action replaces an older queued one, so the newest
    /// intent wins. `EntityId` carries the characteristic, so a lamp's brightness and color
    /// temperature occupy separate slots; `turnOn` and `turnOff` share the switcher slot on purpose —
    /// replaying both would be contradictory.
    private var failedActions: [EntityId: (action: HomeManagableAction, attempt: Int, runId: UUID?, heating: HeatingWriteContext.Context?, intent: UInt64)] = [:]
    /// The number of the newest intent per entity. A command that finishes after a newer one for its entity
    /// started is stale: it neither queues a retry nor becomes the last heating write.
    private var newestIntent: [EntityId: UInt64] = [:]
    /// Changed entity states on their way to the database. One task drains it in order, so a burst
    /// of events (the adapter's full resync on every reconnect) uses one database connection at a
    /// time instead of one query per event at once.
    private let persistQueue: AsyncStream<EntityStorageItem>.Continuation
    /// Far above one full resync (~200 entities); only reached while the database is stuck. The
    /// oldest queued states are dropped first. An entity whose only queued state is dropped is
    /// missing from the history until its next change, because a replay of that value is not queued.
    nonisolated private static let persistQueueLimit = 5_000
    /// States dropped since the queue last had room again; keeps a stuck database from flooding the log.
    private var droppedPersistItems = 0
    private var liveness = HomeKitLiveness(startedAt: Date())

    /// - Parameters:
    ///   - retryTicks: Cadence at which queued failed actions are retried. Pass a stream to drive the
    ///     retries deterministically; the default is a 5s timer.
    ///   - storageUpkeep: What the database upkeep steps do; `nil` does nothing.
    ///   - onReportedChange: Called with each changed state set by `report`; the server yields `HomeEvent.change`.
    ///   - persistRetryDelays: Pauses between the attempts to save one entity state; one more attempt
    ///     than there are delays.
    ///   - logger: Where the manager logs; a test passes one with its own handler to read the log lines.
    public init(getAdapter: @escaping () async -> (any EntityAdapterable)?,
                storageRepo: StorageRepository,
                notificationSender: NotificationSender,
                location: Location,
                journal: Journal = Journal(store: InMemoryJournalStore()),
                commandCache: CommandCache = CommandCache(),
                storageUpkeep: (any StorageUpkeep)? = nil,
                onReportedChange: @escaping @Sendable (EntityStorageItem) -> Void = { _ in },
                retryTicks: AsyncStream<Void>? = nil,
                persistRetryDelays: [Duration] = [.seconds(1), .seconds(5)],
                logger: Logger = Logger(label: "HomeManager")) {
        self.log = logger
        let deliveries = DeliveryQueue(sender: notificationSender)
        self.deliveries = deliveries
        self.journal = journal
        self.commandCache = commandCache
        self.storageUpkeep = storageUpkeep
        self.onReportedChange = onReportedChange
        self.getAdapter = getAdapter
        self.storageRepo = storageRepo
        self.location = location

        let (persistStream, persistQueue) = AsyncStream<EntityStorageItem>.makeStream(bufferingPolicy: .bufferingNewest(Self.persistQueueLimit))
        self.persistQueue = persistQueue
        // Normal priority: a background consumer is starved under load. A slow database still never delays a
        // command, because the queue is a separate task that commands only yield into (ADR-004).
        Task.detached { [storageRepo, log] in
            for await item in persistStream {
                await Self.persist(item, in: storageRepo, retryDelays: persistRetryDelays, log: log)
            }
        }

        let ticks = retryTicks ?? Self.timerRetryTicks()
        // Weak: the loop must not keep the manager alive; it ends with the manager or with the ticks.
        Task.detached(priority: .low) { [weak self] in
            for await _ in ticks {
                guard let self else { return }
                let queued = await self.popAllFailedActions()
                for (action, attempt, runId, heating, intent) in queued {
                    self.log.debug("Performing failed action again: \(action) [attempt \(attempt + 1)/\(Self.maxAttempts)]")
                    await self.perform(action, attempt: attempt, runId: runId, heating: heating, intent: intent)
                }
            }
        }
    }

    deinit {
        // Ends the persist consumer, so a manager that is gone leaves no task behind.
        persistQueue.finish()
    }

    /// Production retry cadence: a tick every 5s (the shared timer aligns its first tick to the next
    /// minute boundary).
    private static func timerRetryTicks() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let timer = Task.detached(priority: .low) {
            for await _ in Timer.publish(every: .seconds(5)) {
                continuation.yield(())
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in timer.cancel() }
        return stream
    }

    /// Remembers the last stored state of every entity, so the adapter's resync after a start is no change.
    /// Run once at start, before the first report is processed; a failed load leaves no state remembered.
    ///
    /// - Parameter sleep: Waits out `timeout`; stands in for `Task.sleep` so tests need no real time.
    public func loadCurrentStates(timeout: Duration,
                                  sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) async {
        // Unstructured tasks race, so a query that ignores cancellation cannot hold up the start; the first answer wins.
        let (outcomes, outcomeSink) = AsyncStream<Result<[EntityStorageItem], any Error>>.makeStream()
        let query = Task { [storageRepo] in
            do {
                outcomeSink.yield(.success(try await storageRepo.getAllCurrent()))
            } catch {
                outcomeSink.yield(.failure(error))
            }
        }
        let timer = Task {
            do {
                try await sleep(timeout)
                outcomeSink.yield(.failure(LoadTimeout()))
            } catch {
                // cancelled because the query answered first
            }
        }
        var iterator = outcomes.makeAsyncIterator()
        // No task finishes the stream, so it ends without an answer only when the start itself is cancelled.
        let outcome = await iterator.next() ?? .failure(CancellationError())
        outcomeSink.finish()
        query.cancel()
        timer.cancel()

        await loadDecisionState()

        switch outcome {
        case .success(let stored):
            // a report that arrived during the load is newer than the stored state
            for item in stored where currentStates[item.entityId] == nil {
                currentStates[item.entityId] = item
            }
            log.info("Loaded the stored entity states", metadata: ["count": "\(stored.count)"])
            await loadRecentReadings(of: stored)
        case .failure(let error):
            log.critical("Started without the stored entity states, replays count as changes until each entity changes", metadata: ["error": "\(error)"])
        }
    }

    private struct LoadTimeout: Error {}

    /// Loads what the automations decide on and the database alone holds: the last command per radiator. A failed read leaves it empty and logs; the decision then runs without it.
    private func loadDecisionState() async {
        for write in await journal.lastHeatingWrites() where lastCommands[Self.key(of: write.entityId)] == nil {
            lastCommands[Self.key(of: write.entityId)] = write
        }
    }

    /// Remembers the changes of the last `readingRetention` of every entity that changed within it, so the rise a
    /// decision looks for survives a restart. A failed read leaves that entity without history.
    private func loadRecentReadings(of stored: [EntityStorageItem]) async {
        let cutoff = Date().addingTimeInterval(-Self.readingRetention)
        for item in stored where item.timestamp >= cutoff {
            do {
                let history = try await storageRepo.getHistory(for: item.entityId, startDate: cutoff, endDate: nil, cursor: nil, limit: Self.readingLimit)
                // changes reported while the load ran are newer and already in front
                let known = Set((recentReadings[item.entityId] ?? []).map(\.timestamp))
                recentReadings[item.entityId, default: []] += history.filter { !known.contains($0.timestamp) }
            } catch {
                log.error("Failed to load the recent readings", metadata: ["entityId": "\(item.entityId)", "error": "\(error)"])
            }
        }
    }

    nonisolated private static func key(of radiator: EntityId) -> String {
        "\(radiator.placeId)/\(radiator.name)"
    }

    public func getCurrentEntity(with entityId: EntityId) async throws -> EntityStorageItem {
        if let item = currentStates[entityId] {
            return item
        }
        // Memory only, so a decision never waits for the database: an entity neither loaded at the start nor
        // reported since is unknown.
        throw OptionalError.notFound
    }

    public func lastReports() -> [String: Date] {
        Dictionary(uniqueKeysWithValues: lastReportBySource.map { ($0.key.rawValue, $0.value) })
    }

    public func lastReport(of entityId: EntityId) -> Date? {
        currentStates[entityId]?.lastReport
    }

    public func lastHeatingWrite(of radiator: EntityId) async -> HeatingWrite? {
        lastCommands[Self.key(of: radiator)]
    }

    public func getAllEntitiesLive() async throws -> [EntityStorageItem] {
        log.info("getAllEntitiesLive() — starting distributed actor call")
        let start = ContinuousClock.now
        let entities = try await getAdapter().get(with: log).getAllEntitiesLive()
        let duration = start.duration(to: .now)
        log.info("getAllEntitiesLive() — returned \(entities.count) entities in \(duration)")
        return entities
    }

    public func listThermostats() async throws -> [Thermostat] {
        try await getAdapter().get(with: log).listThermostats()
    }

    public func readThermostat(_ thermostat: Thermostat) async throws -> [EntityStorageItem] {
        try await getAdapter().get(with: log).readThermostat(thermostat)
    }

    public func findEntity(_ entityId: EntityId) async throws {
        guard !reportedEntities.contains(entityId) else { return }
        return try await getAdapter().get(with: log).findEntity(entityId)
    }

    public func perform(_ action: HomeManagableAction) async {
        // Round values to prevent excessive HomeKit updates
        let roundedAction = action.rounded()
        let intent = (newestIntent[roundedAction.entityId] ?? 0) &+ 1
        newestIntent[roundedAction.entityId] = intent
        await perform(roundedAction, attempt: 0, runId: AutomationRunContext.runId, heating: HeatingWriteContext.current, intent: intent)
    }

    /// - Parameter runId: Passed explicitly because the retry loop runs detached, without the
    ///   `AutomationRunContext` task local of the original run; `heating` likewise for `HeatingWriteContext`.
    private func perform(_ action: HomeManagableAction, attempt: Int, runId: UUID?, heating: HeatingWriteContext.Context?, intent: UInt64) async {
        // Cancellation is honoured at command boundaries only: a superseded automation run must not
        // start further commands, but a command that already started always runs to completion (see
        // the shield below). Checked before logging so a skipped command produces no log entry.
        guard !Task.isCancelled else {
            log.debug("Skipping action of a cancelled run: [\(action)]")
            return
        }
        // A new command supersedes the queued retry of its entity, also as a duplicate: the newest intent wins.
        if attempt == 0 {
            failedActions[action.entityId] = nil
        } else if newestIntent[action.entityId] != intent {
            log.debug("Dropping the retry of a superseded command: [\(action)]")
            return
        }

        // Log action and check if it's a duplicate (cache hit)
        let hasCacheHit = await commandCache.isDuplicate(action)
        let entry = ActionLogItem(action: action,
                                  hasCacheHit: hasCacheHit,
                                  runId: runId,
                                  reason: heating?.reason,
                                  planTargetInC: heating?.planTargetInC)
        journal.recordCommand(entry)
        log.info("Command", metadata: [
            "entity": "\(action.entityId)",
            "action": "\(action.actionName)",
            "reason": "\(heating?.reason.rawValue ?? "none")",
            "run": "\(runId?.uuidString ?? "none")",
            "cacheHit": "\(hasCacheHit)"
        ])

        if hasCacheHit {
            return
        }

        // Not a cache hit - execute the action
        log.debug("Executing action: [\(action)]")

        do {
            let adapter = try await getAdapter().get(with: log)

            // Shield the in-flight command from the caller's cancellation: an unstructured task
            // inherits priority, task locals and actor isolation but not cancellation, so a
            // cancelled run can no longer abort the remote call mid-flight and leave a device half
            // configured. The remote call brings its own timeout, so this cannot hang forever.
            let command = Task { try await adapter.perform(action) }
            try await command.value

            // Only a command that reached the device may deduplicate its successors.
            await commandCache.markExecuted(action)
            liveness.recordCommandSuccess(at: Date())
            if newestIntent[action.entityId] == intent, let heating, let write = HeatingWrite(action: action, context: heating) {
                lastCommands[Self.key(of: write.entityId)] = write
            }
        } catch {
            liveness.recordCommandFailure(error, at: Date())
            journal.markCommandFailed(entry.id)
            let entityId = action.entityId

            if let entity = try? await getCurrentEntity(with: entityId) {
                log.error("(\(entityId)) entity \(entity)")
            }
            log.error("(\(entityId)) Failed to perform action [\(action), attempt: \(attempt + 1)/\(Self.maxAttempts)]\n\(error)")

            let nextAttempt = attempt + 1
            if newestIntent[entityId] != intent {
                log.debug("Not retrying a command a newer one superseded: [\(action)]")
            } else if nextAttempt < Self.maxAttempts {
                failedActions[entityId] = (action, nextAttempt, runId, heating, intent)
            } else {
                log.critical("Giving up on action", metadata: ["action": "\(action)", "attempts": "\(Self.maxAttempts)"])
            }
        }
    }

    public func queuedRetry(of entityId: EntityId) async -> HomeManagableAction? {
        failedActions[entityId]?.action
    }

    public func trigger(scene sceneName: String) async {
        // No explicit cache reset here: executing a scene changes the affected devices, and those
        // per-characteristic changes echo back through the adapter into `addEntityHistory`, where
        // `invalidateContradictedCommands(for:)` resets any cached command they contradict. This is
        // the same path that handles scenes activated from outside the server, so both are covered
        // uniformly without the server needing to know a scene's entity membership.
        log.info("Triggering scene '\(sceneName)' — starting distributed actor call")
        let start = ContinuousClock.now
        do {
            try await getAdapter().get(with: log).trigger(scene: sceneName)
            liveness.recordCommandSuccess(at: Date())
            let duration = start.duration(to: .now)
            log.info("Triggering scene '\(sceneName)' — completed in \(duration)")
        } catch {
            liveness.recordCommandFailure(error, at: Date())
            let duration = start.duration(to: .now)
            log.error("Failed to trigger scene '\(sceneName)' after \(duration)\n\(error)")
        }
    }

    @discardableResult
    public func report(_ entityId: EntityId, value: Value, origin: Origin) async throws -> Bool {
        // Like `perform`: a run that was superseded must not change state any more. Checked on this actor, so it is
        // atomic with the write: the lane cancels the old run before the new one starts.
        try Task.checkCancellation()
        guard entityId.isServerOwned else { throw ReportError.notServerOwned(entityId) }
        guard let item = EntityStorageItem(entityId: entityId, value: value, origin: origin) else {
            throw ReportError.valueDoesNotFit(entityId)
        }
        // No suspension point between the check, the state, the persist and the emit: the state holds before the
        // event reaches the stream, and two reports of one entity cannot interleave.
        let changed = record(item)
        if let changed {
            onReportedChange(changed)
        }
        await invalidateContradictedCommands(for: item)
        return changed != nil
    }

    public func states(of type: CharacteristicsType) async -> [EntityStorageItem] {
        currentStates.values.filter { $0.entityId.characteristicType == type }
    }

    @discardableResult
    public func addEntityHistory(_ item: EntityStorageItem) async -> Bool {
        let changed = record(item) != nil
        // A freshly observed state can reveal that the device drifted away from what the server last
        // commanded — e.g. a scene activated outside the server (HomeKit only surfaces scenes as the
        // per-characteristic changes they produce, which arrive here), or a manual change. Reset any
        // cached command this state contradicts so the automation engine — which re-evaluates this
        // same event right after — is allowed to re-issue it. A state that confirms the command (the
        // command's own echo) is not contradicted, so deduplication is preserved and no command loop
        // occurs. Done before this returns, so the cache is already reset before the automation runs.
        //
        // Invariant this relies on: no `.change`-triggered automation commands its own trigger
        // entity. Today that holds (MotionAtNight triggers on motion/contact and commands lights,
        // WindowOpen commands nothing). An automation that violated it would not get its command
        // re-issued after the drift was healed, because the `changed` gate stops a
        // value-identical replay from triggering the automation again.
        await invalidateContradictedCommands(for: item)
        return changed
    }

    private func invalidateContradictedCommands(for item: EntityStorageItem) async {
        let invalidatedActions = await commandCache.invalidateContradictedCommands(for: item)
        if !invalidatedActions.isEmpty {
            log.info("Invalidated \(invalidatedActions.count) cached command(s) for \(item.entityId) due to state drift: \(invalidatedActions)")
        }
    }

    /// Sets the state and queues it for the database, all in one synchronous section: no suspension point, so
    /// reports of one entity apply, emit and persist in the order they arrive.
    /// - Returns: The stored state when it is a change, `nil` for a value-identical replay.
    private func record(_ item: EntityStorageItem) -> EntityStorageItem? {
        log.debug("Adding entity item to storage \(item.entityId)")
        // Every report from HomeKit counts, a value-identical replay too: it proves HomeKit still delivers.
        // A change of another origin (server, polling job) proves nothing about HomeKit.
        if item.origin == .homekit {
            liveness.recordEvent(at: Date())
        }
        reportedEntities.insert(item.entityId)
        let reportedAt = Date()
        lastReportBySource[item.origin] = reportedAt

        // Only the values decide whether this is new information. An unknown entity counts as a
        // change so nothing is ever swallowed on the first sighting.
        guard currentStates[item.entityId]?.hasSameValue(as: item) != true else {
            // A replay keeps the known state, so its timestamp stays the time of the last change.
            currentStates[item.entityId]?.lastReport = reportedAt
            return nil
        }
        var state = item
        state.lastReport = reportedAt
        currentStates[item.entityId] = state
        remember(reading: item)

        // Persist item in the background to avoid blocking automation execution
        switch persistQueue.yield(item) {
        case .dropped(let dropped):
            droppedPersistItems += 1
            if droppedPersistItems == 1 || droppedPersistItems.isMultiple(of: 500) {
                log.warning("Persist queue full, dropped \(droppedPersistItems) entity item(s) so far, last one \(dropped.entityId)")
            }
        case .enqueued(let remaining) where droppedPersistItems > 0 && remaining >= Self.persistQueueLimit / 2:
            log.notice("Persist queue draining again after dropping \(droppedPersistItems) entity item(s)")
            droppedPersistItems = 0
        default:
            break
        }
        return state
    }

    /// Retries inside the serial queue instead of forgetting the current state: a forgotten state would make
    /// the next identical replay count as a change and trigger automations again.
    nonisolated private static func persist(_ item: EntityStorageItem, in storageRepo: StorageRepository, retryDelays: [Duration], log: Logger) async {
        var attempt = 0
        while true {
            do {
                try await persistOnce(item, in: storageRepo)
                return
            } catch {
                guard attempt < retryDelays.count else {
                    log.critical("Failed to persist entity item \(item.entityId) after \(attempt + 1) attempts: \(error)")
                    return
                }
                log.warning("Failed to persist entity item \(item.entityId), retrying: \(error)")
                try? await Task.sleep(for: retryDelays[attempt])
                attempt += 1
            }
        }
    }

    nonisolated private static func persistOnce(_ item: EntityStorageItem, in storageRepo: StorageRepository) async throws {
        // Skip a state the database already holds: it keeps a retry from saving a state twice, and covers
        // a start whose load of the stored states failed, so the adapter's resync counted as changes.
        if let currentItem = try await storageRepo.getCurrent(item.entityId), currentItem.hasSameValue(as: item) {
            return
        }
        try await storageRepo.add(item)
    }

    public func getLocation() -> Location {
        return location
    }

    private func remember(reading item: EntityStorageItem) {
        let cutoff = item.timestamp.addingTimeInterval(-Self.readingRetention)
        var readings = recentReadings[item.entityId] ?? []
        readings.insert(item, at: 0)
        readings.removeAll { $0.timestamp < cutoff }
        if readings.count > Self.readingLimit { readings.removeLast(readings.count - Self.readingLimit) }
        recentReadings[item.entityId] = readings
    }

    public func getEntityHistory(with entityId: EntityId, since: Date) async -> [EntityStorageItem] {
        (recentReadings[entityId] ?? []).filter { $0.timestamp >= since }
    }

    public func getFullEntityHistory(with entityId: EntityId, limit: Int) async -> [EntityStorageItem] {
        let recent = recentReadings[entityId] ?? []
        var stored: [EntityStorageItem] = []
        do {
            stored = try await storageRepo.getHistory(for: entityId, startDate: nil, endDate: nil, cursor: nil, limit: limit)
        } catch {
            log.error("Failed to read the entity history", metadata: ["entityId": "\(entityId)", "error": "\(error)"])
        }
        let known = Set(recent.map(\.timestamp))
        let merged = recent + stored.filter { !known.contains($0.timestamp) }
        return Array(merged.sorted { $0.timestamp > $1.timestamp }.prefix(limit))
    }

    public func lastNotificationDate(id: String) async -> Date? {
        await deliveries.lastPushDate(id: id)
    }

    /// Every alert push is one journal entry, linked to the run that sent it.
    nonisolated private static func record(_ delivery: Delivery, in journal: Journal) {
        guard case let .push(title, message, id, _) = delivery else { return }
        journal.recordPush(JournalPush(runId: AutomationRunContext.runId, title: title, message: message, pushId: id))
    }

    public func deliver(_ delivery: Delivery) async {
        Self.record(delivery, in: journal)
        await deliveries.deliver(delivery)
    }

    public func homeKitHealth() async -> HomeKitHealth {
        let isConnected = await getAdapter() != nil
        return liveness.evaluate(isConnected: isConnected, at: Date())
    }

    public func performStorageUpkeep(_ step: StorageUpkeepStep, now: Date) async throws {
        try await storageUpkeep?.perform(step, now: now)
    }

    private func popAllFailedActions() -> [(action: HomeManagableAction, attempt: Int, runId: UUID?, heating: HeatingWriteContext.Context?, intent: UInt64)] {
        let queued = Array(failedActions.values)
        failedActions.removeAll()
        return queued
    }
}
