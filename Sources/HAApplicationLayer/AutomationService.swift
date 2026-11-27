//
//  AutomationService.swift
//  
//
//  Created by Julian Kahnert on 01.07.24.
//

import Foundation
import HAModels
import Logging

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
        var reported = false

        var isBusy: Bool { worker != nil }

        func age(now: Date) -> TimeInterval {
            guard let oldest = inFlight ?? pending.first?.enqueuedAt else { return 0 }
            return max(0, now.timeIntervalSince(oldest))
        }
    }

    private var lanes: [String: Lane] = [:]
    private var runningTasks: [String: Task<Void, Never>] = [:]
    /// Names whose current task was cancelled by `stopAutomation`, so its run ends as `stopped`
    /// rather than `superseded`.
    private var stopRequested: Set<String> = []

    public init(using homeManager: HomeManagable,
                runs: AutomationRunRepository,
                automations: [any Automatable] = [],
                repository: any AutomationRepository = InMemoryAutomationRepository()) throws {
        self.homeManager = homeManager
        self.runs = runs
        self.automations = automations
        self.repository = repository
    }

    /// Replaces the deployed automations and stores them. An automation that was deployed before keeps its active state.
    public func deploy(_ newAutomations: [any Automatable]) async throws {
        let previous = automations
        automations = newAutomations.map { automation in
            var automation = automation
            if let existing = previous.first(where: { $0.name == automation.name }) {
                automation.isActive = existing.isActive
            }
            return automation
        }
        try await repository.save(automations)
    }

    public func setAutomationActive(with name: String, to value: Bool) async throws {
        automations = automations.map { automation in
            var automation = automation
            if automation.name == name {
                automation.isActive = value
            }
            return automation
        }
        try await repository.save(automations)
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
            let age = lane.age(now: now)
            if age > limit {
                guard !lane.reported else { continue }
                lane.reported = true
                log.critical("Automation lane is backed up", metadata: ["automation": "\(name)", "ageSeconds": "\(Int(age))", "waiting": "\(lane.pending.count)"])
            } else if !lane.isBusy {
                lane.reported = false
            }
        }
    }

    private func enqueue(_ event: HomeEvent, enqueuedAt: Date, into automation: any Automatable) {
        let lane = lanes[automation.name] ?? Lane()
        lanes[automation.name] = lane
        if automation.collapsesChanges, case .change(let item) = event {
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
        lane.reported = false
        lane.worker = nil
    }

    private func process(_ event: HomeEvent, with automation: any Automatable) async {
        do {
            guard try await automation.shouldTrigger(with: event, using: self.homeManager) else {
                return
            }

            self.log.info("Running automation \(automation.name)")
            let runId = automation.recordsRuns ? UUID() : nil
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
                    let stopped = await self.consumeStopRequest(for: automation.name)
                    await self.finish(await recording.value, outcome: stopped ? .stopped : .superseded)
                } catch {
                    self.log.error("Automation failed with error - \(error)")
                    await self.finish(await recording.value, outcome: .failed, error: String(describing: error))
                }

                // cancel the current task after completion to get correct results of getActiveAutomationNames
                withUnsafeCurrentTask { currentTask in
                    currentTask?.cancel()
                }
            }
            self.set(task: task, with: automation.name)
        } catch {
            self.log.error("Automation shouldTrigger failed with error - \(error)")
        }
    }

    public func getActiveAutomationNames() async -> Set<String> {
        let keys = runningTasks
            .filter { !$0.value.isCancelled }
            .map(\.key)

        log.debug("Found currently active automations \(keys)")
        return Set(keys)
    }

    public func stopAutomation(with name: String) async {
        log.debug("Cancel automation \(name)")
        guard let task = runningTasks[name], !task.isCancelled else { return }
        stopRequested.insert(name)
        task.cancel()
    }

    private func set(task: Task<Void, Never>, with id: String) {
        if let runningTask = runningTasks[id],
           !runningTask.isCancelled {
            runningTask.cancel()
        }

        runningTasks[id] = task
    }

    private func consumeStopRequest(for name: String) -> Bool {
        stopRequested.remove(name) != nil
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
            log.error("Failed to record automation run - \(error)")
            return nil
        }
    }

    private func finish(_ runId: UUID?, outcome: AutomationRun.Outcome, error: String? = nil) async {
        guard let runId else { return }
        do {
            try await runs.finish(runId, outcome: outcome, endedAt: Date(), errorDescription: error)
        } catch {
            log.error("Failed to finish automation run - \(error)")
        }
    }
}
