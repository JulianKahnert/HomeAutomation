//
//  AutomationService.swift
//  
//
//  Created by Julian Kahnert on 01.07.24.
//

import Foundation
import HAModels
import Logging
import Shared

public actor AutomationService {
    private let log = Logger(label: "AutomationManager")
    private let homeManager: HomeManagable
    private let runs: AutomationRunRepository
    private let repository: any AutomationRepository
    /// The deployed automation instances; `isActive` is their active state.
    public private(set) var automations: [any Automatable]
    /// One lane per automation name: the events it still has to check, in the order they happened.
    private final class Lane {
        var pending: [(event: HomeEvent, enqueuedAt: Date)] = []
        /// When the event whose `shouldTrigger` is running entered the lane.
        var inFlight: Date?
        var worker: Task<Void, Never>?
        var backlog = BacklogReporter()

        var isBusy: Bool { worker != nil }

        func age(now: Date) -> TimeInterval {
            BacklogReporter.age(ofOldest: inFlight ?? pending.first?.enqueuedAt, now: now)
        }
    }

    private var lanes: [String: Lane] = [:]
    /// Automations the server itself needs (e.g. the database cleanup). They are added when a deploy or the
    /// stored config lacks them, and keep their active state like any other automation.
    private let builtIns: [any Automatable]
    private var runningTasks: [String: Task<Void, Never>] = [:]
    /// The token of each running task by automation name, to tell a stop of this very run from an older one.
    private var runTokens: [String: UUID] = [:]
    /// Tokens of the runs `stopAutomation` cancelled, so such a run ends as `stopped` rather than `superseded`.
    /// Every run removes its own token in `ended`, however it ends, so none goes stale.
    private var stopRequested: Set<UUID> = []

    public init(using homeManager: HomeManagable,
                runs: AutomationRunRepository,
                automations: [any Automatable] = [],
                builtIns: [any Automatable] = [],
                repository: any AutomationRepository = InMemoryAutomationRepository()) throws {
        self.homeManager = homeManager
        self.runs = runs
        self.builtIns = builtIns
        self.automations = Self.adding(builtIns, to: automations)
        self.repository = repository
    }

    /// The save that was handed over last; the next one waits for it, so an older snapshot never lands after a newer one.
    private var saveTail: Task<Void, any Error>?

    /// Stores the current automations. The snapshot is taken and the tail is set in the same synchronous section,
    /// so the saves leave in the order the changes were made, however the callers' tasks are scheduled.
    private func startSave(location: Location? = nil) -> Task<Void, any Error> {
        let snapshot = automations
        let previous = saveTail
        let task = Task { [repository] in
            _ = await previous?.result
            try await repository.save(snapshot, location: location)
        }
        saveTail = task
        return task
    }

    /// Replaces the deployed automations and stores them, with the config's location in the same snapshot.
    /// An automation that was deployed before keeps its active state.
    public func deploy(_ newAutomations: [any Automatable], location: Location? = nil) async throws {
        try await startDeploy(newAutomations, location: location).value
    }

    /// Like ``deploy(_:location:)``, but returns as soon as the automations are swapped in memory. The returned task
    /// ends with the save; the saves of earlier changes go first. The event loop uses it so that a slow database never holds it.
    public func startDeploy(_ newAutomations: [any Automatable], location: Location? = nil) -> Task<Void, any Error> {
        let previous = automations
        automations = Self.adding(builtIns, to: newAutomations).map { automation in
            var automation = automation
            if let existing = previous.first(where: { $0.name == automation.name }) {
                automation.isActive = existing.isActive
            }
            return automation
        }
        return startSave(location: location)
    }

    private static func adding(_ builtIns: [any Automatable], to automations: [any Automatable]) -> [any Automatable] {
        automations + builtIns.filter { builtIn in !automations.contains { $0.name == builtIn.name } }
    }

    public func setAutomationActive(with name: String, to value: Bool) async throws {
        try await startSettingActive(with: name, to: value).value
    }

    /// Like ``setAutomationActive(with:to:)``, but returns as soon as the state is set in memory; the returned task ends
    /// with the save.
    public func startSettingActive(with name: String, to value: Bool) -> Task<Void, any Error> {
        automations = automations.map { automation in
            var automation = automation
            if automation.name == name {
                automation.isActive = value
            }
            return automation
        }
        return startSave()
    }

    /// Stores the current automations (and the location, when given) and waits for it.
    public func save(location: Location? = nil) async throws {
        try await startSave(location: location).value
    }

    /// Hands the event to the lane of every active automation and returns without waiting for any `shouldTrigger`.
    public func trigger(with event: HomeEvent) async {
        let now = Date()
        for automation in automations where automation.isActive {
            enqueue(event, enqueuedAt: now, into: automation)
        }
    }

    /// Waits until every lane is empty and idle (for tests).
    public func waitUntilIdle() async {
        while lanes.values.contains(where: { $0.isBusy }) {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    /// The age of the oldest event each lane has not finished checking, in seconds; 0 for an idle lane.
    public func laneAges(now: Date = Date()) -> [String: TimeInterval] {
        var ages: [String: TimeInterval] = [:]
        for automation in automations {
            ages[automation.name] = lanes[automation.name]?.age(now: now) ?? 0
        }
        return ages
    }

    /// Logs one critical message per backlog naming each automation whose lane is older than `limit`.
    /// The lane is reported again only after it has drained.
    public func reportBacklogs(olderThan limit: TimeInterval, now: Date = Date()) {
        for (name, lane) in lanes {
            guard let age = lane.backlog.report(age: lane.age(now: now), olderThan: limit) else { continue }
            log.critical("Automation lane is backed up", metadata: ["automation": "\(name)", "ageSeconds": "\(Int(age))", "waiting": "\(lane.pending.count)"])
        }
    }

    private func enqueue(_ event: HomeEvent, enqueuedAt: Date, into automation: any Automatable) {
        let lane = lanes[automation.name] ?? Lane()
        lanes[automation.name] = lane
        if automation.lanePolicy != .runEach, case .change(let item) = event {
            lane.pending.removeAll { entry in
                if case .change(let waiting) = entry.event { return waiting.entityId == item.entityId }
                return false
            }
        }
        lane.pending.append((event, enqueuedAt))
        guard lane.worker == nil else { return }
        let name = automation.name
        lane.worker = Task { await self.work(lane: name) }
    }

    /// Works through one lane in order; each event waits for the `shouldTrigger` of the one before it.
    private func work(lane name: String) async {
        guard let lane = lanes[name] else { return }
        while !lane.pending.isEmpty {
            let entry = lane.pending.removeFirst()
            lane.inFlight = entry.enqueuedAt
            if let automation = automations.first(where: { $0.name == name }), automation.isActive {
                await process(entry.event, with: automation)
            }
            lane.inFlight = nil
        }
        lane.worker = nil
    }

    private func process(_ event: HomeEvent, with automation: any Automatable) async {
        do {
            guard try await automation.shouldTrigger(with: event, using: self.homeManager) else {
                return
            }

            if automation.lanePolicy == .skipWhileRunning, self.isRunning(automation.name) {
                self.log.info("Automation is still running, not starting it again", metadata: ["automation": "\(automation.name)"])
                return
            }

            self.log.info("Running automation", metadata: ["automation": "\(automation.name)"])
            let runId = automation.recordsRuns ? UUID() : nil
            let token = UUID()
            let task = Task {
                // Persisted alongside `execute`: the database must never delay the first command.
                let recording = Task { await self.record(runId, of: automation, for: event) }
                do {
                    try await AutomationRunContext.$runId.withValue(runId) {
                        try await AutomationRunContext.$event.withValue(event) {
                            try await automation.execute(using: self.homeManager)
                        }
                    }
                    await self.finish(await recording.value, outcome: .completed)
                } catch is CancellationError {
                    // read before `ended` removes the token; a stop that arrives later finds the run gone
                    let stopped = await self.hasStopRequest(token)
                    await self.finish(await recording.value, outcome: stopped ? .stopped : .superseded)
                } catch {
                    self.log.error("Automation failed", metadata: ["automation": "\(automation.name)", "error": "\(error)"])
                    await self.finish(await recording.value, outcome: .failed, error: String(describing: error))
                }
                await self.ended(token: token, name: automation.name)
            }
            self.set(task: task, token: token, with: automation.name)
            if automation.lanePolicy == .runEach {
                await task.value
            }
        } catch {
            self.log.error("Automation shouldTrigger failed", metadata: ["automation": "\(automation.name)", "error": "\(error)"])
        }
    }

    public func stopAutomation(with name: String) async {
        log.debug("Cancel automation", metadata: ["automation": "\(name)"])
        guard let task = runningTasks[name], let token = runTokens[name] else { return }
        stopRequested.insert(token)
        task.cancel()
    }

    private func isRunning(_ name: String) -> Bool {
        runningTasks[name] != nil
    }

    private func set(task: Task<Void, Never>, token: UUID, with id: String) {
        runningTasks[id]?.cancel()

        runningTasks[id] = task
        runTokens[id] = token
    }

    private func hasStopRequest(_ token: UUID) -> Bool {
        stopRequested.contains(token)
    }

    /// The last thing every run does, with no suspension point in it: drops the run's stop token and, when no newer
    /// run replaced it, the run itself. So no token goes stale, however the run ended.
    private func ended(token: UUID, name: String) {
        stopRequested.remove(token)
        if runTokens[name] == token {
            runningTasks[name] = nil
            runTokens[name] = nil
        }
    }

    /// - Returns: `runId` once the run is stored, `nil` when nothing was (or could be) recorded.
    private func record(_ runId: UUID?, of automation: any Automatable, for event: HomeEvent) async -> UUID? {
        guard let runId else { return nil }

        let startedAt = Date()
        var trigger = event.trigger
        if let detail = await automation.triggerSummary(for: event, using: homeManager) {
            trigger = trigger.appending(detail)
        }
        let run = AutomationRun(id: runId, automationName: automation.name, startedAt: startedAt, trigger: trigger, outcome: .running)
        do {
            try await runs.add(run)
            return runId
        } catch {
            log.error("Failed to record automation run", metadata: ["automation": "\(automation.name)", "error": "\(error)"])
            return nil
        }
    }

    private func finish(_ runId: UUID?, outcome: AutomationRun.Outcome, error: String? = nil) async {
        guard let runId else { return }
        do {
            try await runs.finish(runId, outcome: outcome, endedAt: Date(), errorDescription: error)
        } catch {
            log.error("Failed to finish automation run", metadata: ["runId": "\(runId)", "error": "\(error)"])
        }
    }
}
