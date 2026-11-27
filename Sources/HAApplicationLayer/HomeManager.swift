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

    private let log = Logger(label: "HomeManager")
    private let windowManager: WindowManager
    private let commandCache: CommandCache
    private let journal: Journal

    private let getAdapter: () async -> (any EntityAdapterable)?
    private let location: Location
    private let storageRepo: StorageRepository
    private let deliveries: DeliveryQueue
    private let heatingWrites: (any HeatingWriteRepository)?
    private let fireplaceSwitches: (any FireplaceRepository)?
    private let storageUpkeep: (any StorageUpkeep)?
    /// Tells the automations about a switch of the fireplace; the server yields `HomeEvent.fireplaceChanged`.
    private let onFireplaceSwitch: @Sendable (FireplaceSwitch) -> Void
    /// The newest fireplace switch, loaded once from the database. It also holds a switch the database could
    /// not save, so an end of the fireplace stays an end and `FireplaceTimeout` does not repeat itself.
    private var fireplace: FireplaceSwitch??
    /// The last command that reached each radiator, keyed by room and radiator name; loaded from the database at
    /// start and kept current by `record`, so a decision never reads the database.
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
    /// One retry slot per entity: a newer failed action replaces an older queued one, so the newest
    /// intent wins. `EntityId` carries the characteristic, so a lamp's brightness and color
    /// temperature occupy separate slots; `turnOn` and `turnOff` share the switcher slot on purpose —
    /// replaying both would be contradictory.
    private var failedActions: [EntityId: (action: HomeManagableAction, attempt: Int, runId: UUID?, heating: HeatingWriteContext.Context?)] = [:]
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
    ///   - heatingWrites: Where the writes to radiators are recorded with their reason; `nil` records none.
    ///   - fireplaceSwitches: Where the fireplace switches are stored; `nil` keeps them in memory only.
    ///   - storageUpkeep: What the database upkeep steps do; `nil` does nothing.
    ///   - onFireplaceSwitch: Called after each switch of the fireplace, to tell the automations.
    ///   - persistRetryDelays: Pauses between the attempts to save one entity state; one more attempt
    ///     than there are delays.
    ///   - outdoorTemperature: The latest stored outdoor temperature reading in °C, `nil` without one;
    ///     shown in the window Live Activity.
    public init(getAdapter: @escaping () async -> (any EntityAdapterable)?,
                storageRepo: StorageRepository,
                notificationSender: NotificationSender,
                location: Location,
                journal: Journal = Journal(store: InMemoryJournalStore()),
                commandCache: CommandCache = CommandCache(),
                heatingWrites: (any HeatingWriteRepository)? = nil,
                fireplaceSwitches: (any FireplaceRepository)? = nil,
                storageUpkeep: (any StorageUpkeep)? = nil,
                onFireplaceSwitch: @escaping @Sendable (FireplaceSwitch) -> Void = { _ in },
                retryTicks: AsyncStream<Void>? = nil,
                persistRetryDelays: [Duration] = [.seconds(1), .seconds(5)],
                outdoorTemperature: @escaping @Sendable () async -> Double? = { nil }) {
        let deliveries = DeliveryQueue(sender: notificationSender)
        self.deliveries = deliveries
        self.windowManager = WindowManager(deliver: { delivery in
            Self.record(delivery, in: journal)
            await deliveries.deliver(delivery)
        }, outdoorTemperature: outdoorTemperature)
        self.journal = journal
        self.commandCache = commandCache
        self.heatingWrites = heatingWrites
        self.fireplaceSwitches = fireplaceSwitches
        self.storageUpkeep = storageUpkeep
        self.onFireplaceSwitch = onFireplaceSwitch
        self.getAdapter = getAdapter
        self.storageRepo = storageRepo
        self.location = location

        let (persistStream, persistQueue) = AsyncStream<EntityStorageItem>.makeStream(bufferingPolicy: .bufferingNewest(Self.persistQueueLimit))
        self.persistQueue = persistQueue
        Task.detached(priority: .background) { [storageRepo, log] in
            for await item in persistStream {
                await Self.persist(item, in: storageRepo, retryDelays: persistRetryDelays, log: log)
            }
        }

//        Task {
//            let adapter = await getAdapter()
//            let entityStream = await adapter.getEntityStream()
//            for await entityStorageItem in entityStream {
//                self.log.info("Received storage item \(entityStorageItem)")
//                await self.addEntityHistory(entityStorageItem)
//                self.entityStreamContinuation.yield(entityStorageItem.entityId)
//            }
//        }

        let ticks = retryTicks ?? Self.timerRetryTicks()
        Task.detached(priority: .low) {
            for await _ in ticks {
                let queued = await self.popAllFailedActions()
                for (action, attempt, runId, heating) in queued {
                    self.log.debug("Performing failed action again: \(action) [attempt \(attempt + 1)/\(Self.maxAttempts)]")
                    await self.perform(action, attempt: attempt, runId: runId, heating: heating)
                }
            }
        }
    }

    /// Production retry cadence: a tick every 5s (the shared timer aligns its first tick to the next
    /// minute boundary).
    private static func timerRetryTicks() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        Task.detached(priority: .low) {
            for await _ in Timer.publish(every: .seconds(5)) {
                continuation.yield(())
            }
            continuation.finish()
        }
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

    /// Loads what the automations decide on and the database alone holds: the last command per radiator and the
    /// fireplace state. A failed read leaves it empty and logs; the decision then runs without it.
    private func loadDecisionState() async {
        if let heatingWrites {
            do {
                for write in try await heatingWrites.lastWrites() where lastCommands[Self.key(of: write.entityId)] == nil {
                    lastCommands[Self.key(of: write.entityId)] = write
                }
            } catch {
                log.error("Failed to load the last heating commands", metadata: ["error": "\(error)"])
            }
        }
        if fireplace == nil, let fireplaceSwitches {
            do {
                // a switch made while the database was read wins over what it answered
                let stored = try await fireplaceSwitches.latest()
                if fireplace == nil { fireplace = .some(stored) }
            } catch {
                log.error("Failed to read the fireplace state", metadata: ["error": "\(error)"])
            }
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

    public func getPreviousEntity(with entityId: EntityId) async throws -> EntityStorageItem? {
        return try await storageRepo.getPrevious(entityId).get(with: log)
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
        await perform(roundedAction, attempt: 0, runId: AutomationRunContext.runId, heating: HeatingWriteContext.current)
    }

    /// - Parameter runId: Passed explicitly because the retry loop runs detached, without the
    ///   `AutomationRunContext` task local of the original run; `heating` likewise for `HeatingWriteContext`.
    private func perform(_ action: HomeManagableAction, attempt: Int, runId: UUID?, heating: HeatingWriteContext.Context?) async {
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
        }

        // Log action and check if it's a duplicate (cache hit)
        let hasCacheHit = await commandCache.isDuplicate(action)
        let entry = ActionLogItem(action: action,
                                  hasCacheHit: hasCacheHit,
                                  runId: runId,
                                  reason: heating?.reason,
                                  planTargetInC: heating?.planTargetInC)
        journal.recordCommand(entry)

        if hasCacheHit {
            log.info("Skipping duplicate command: [\(action)]")
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
            if let heating, let write = HeatingWrite(action: action, context: heating) {
                await record(write)
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
            if nextAttempt < Self.maxAttempts {
                failedActions[entityId] = (action, nextAttempt, runId, heating)
            } else {
                log.critical("Giving up on action [\(action)] after \(Self.maxAttempts) attempts")
            }
        }
    }

    public func queuedRetry(of entityId: EntityId) async -> HomeManagableAction? {
        failedActions[entityId]?.action
    }

    public func lastFireplaceSwitch() async -> FireplaceSwitch? {
        fireplace.flatMap { $0 }
    }

    public func switchFireplace(isOn: Bool, at date: Date) async -> FireplaceSwitch? {
        let current = await lastFireplaceSwitch()
        guard (current?.isOn ?? false) != isOn else { return nil }
        let new = FireplaceSwitch(timestamp: date, isOn: isOn)
        fireplace = .some(new)
        onFireplaceSwitch(new)
        do {
            try await fireplaceSwitches?.add(new)
        } catch {
            log.error("Failed to store the fireplace switch", metadata: ["isOn": "\(isOn)", "error": "\(error)"])
        }
        return new
    }

    /// Persists a radiator write; a failing database must not fail the command.
    public func record(_ write: HeatingWrite) async {
        if write.sentToDevice { lastCommands[Self.key(of: write.entityId)] = write }
        guard let heatingWrites else { return }
        do {
            try await heatingWrites.add(write)
        } catch {
            log.error("Failed to record heating write", metadata: ["action": "\(write.actionName)", "radiator": "\(write.entityId.name)", "error": "\(error)"])
        }
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
    public func addEntityHistory(_ item: EntityStorageItem) async -> Bool {
        log.debug("Adding entity item to storage \(item.entityId)")
        // Every report from HomeKit counts, a value-identical replay too: it proves HomeKit still delivers.
        // A change of another origin (server, polling job) proves nothing about HomeKit.
        if item.origin == .homekit {
            liveness.recordEvent(at: Date())
        }
        reportedEntities.insert(item.entityId)

        // `EntityStorageItem` is Equatable including its timestamp, so align it before comparing —
        // only the values decide whether this is new information. An unknown entity counts as a
        // change so nothing is ever swallowed on the first sighting.
        let didChange: Bool
        if var knownItem = currentStates[item.entityId] {
            knownItem.timestamp = item.timestamp
            knownItem.origin = item.origin
            didChange = knownItem != item
        } else {
            didChange = true
        }

        // A replay keeps the known state, so its timestamp stays the time of the last change.
        if didChange {
            currentStates[item.entityId] = item
            remember(reading: item)
        }

        // A freshly observed state can reveal that the device drifted away from what the server last
        // commanded — e.g. a scene activated outside the server (HomeKit only surfaces scenes as the
        // per-characteristic changes they produce, which arrive here), or a manual change. Reset any
        // cached command this state contradicts so the automation engine — which re-evaluates this
        // same event right after — is allowed to re-issue it. A state that confirms the command (the
        // command's own echo) is not contradicted, so deduplication is preserved and no command loop
        // occurs. Done synchronously here so the cache is already reset before the automation runs.
        //
        // Invariant this relies on: no `.change`-triggered automation commands its own trigger
        // entity. Today that holds (MotionAtNight triggers on motion/contact and commands lights,
        // WindowOpen commands nothing). An automation that violated it would not get its command
        // re-issued after the drift was healed, because the `didChange` gate above stops a
        // value-identical replay from triggering the automation again.
        let invalidatedActions = await commandCache.invalidateContradictedCommands(for: item)
        if !invalidatedActions.isEmpty {
            log.info("Invalidated \(invalidatedActions.count) cached command(s) for \(item.entityId) due to state drift: \(invalidatedActions)")
        }

        // A value-identical replay is already queued or stored: `currentStates` only holds states loaded
        // from the database or sent through this queue.
        guard didChange else { return false }

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

        return didChange
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
        if var currentItem = try await storageRepo.getCurrent(item.entityId) {
            // we want to exclude the timestamp from the equality comparison, so change the timestamp temporarily
            currentItem.timestamp = item.timestamp
            currentItem.origin = item.origin
            guard item != currentItem else { return }
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

    public func getStoredEntity(with entityId: EntityId) async -> EntityStorageItem? {
        do {
            return try await storageRepo.getCurrent(entityId)
        } catch {
            log.error("Failed to read the stored entity", metadata: ["entityId": "\(entityId)", "error": "\(error)"])
            return nil
        }
    }

    public func getEntityHistory(with entityId: EntityId, since: Date) async -> [EntityStorageItem] {
        (recentReadings[entityId] ?? []).filter { $0.timestamp >= since }
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

    public func markWindowOverdue(entityId: EntityId) async {
        await windowManager.markWindowOverdue(entityId: entityId)
    }

    public func getWindowContentState() async -> WindowContentState {
        await windowManager.contentState()
    }

    public func setWindowOpenState(entityId: EntityId, to state: WindowOpenState?) async {
        await windowManager.setWindowOpenState(entityId: entityId, to: state)
    }

    public func getActionLog(limit: Int?, runId: UUID?) async -> [ActionLogItem] {
        await journal.commands(limit: limit, runId: runId)
    }

    public func clearActionLog() async {
        await journal.clearCommands()
    }

    public func homeKitHealth() async -> HomeKitHealth {
        let isConnected = await getAdapter() != nil
        return liveness.evaluate(isConnected: isConnected, at: Date())
    }

    public func performStorageUpkeep(_ step: StorageUpkeepStep, now: Date) async throws {
        try await storageUpkeep?.perform(step, now: now)
    }

    private func popAllFailedActions() -> [(action: HomeManagableAction, attempt: Int, runId: UUID?, heating: HeatingWriteContext.Context?)] {
        let queued = Array(failedActions.values)
        failedActions.removeAll()
        return queued
    }
}
