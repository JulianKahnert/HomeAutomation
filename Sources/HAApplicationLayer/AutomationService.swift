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
    private let getAutomations: () async -> [any Automatable]
    private var runningTasks: [String: Task<Void, Never>] = [:]
    /// Names whose current task was cancelled by `stopAutomation`, so its run ends as `stopped`
    /// rather than `superseded`.
    private var stopRequested: Set<String> = []

    public init(using homeManager: HomeManagable, runs: AutomationRunRepository, getAutomations: @escaping () async -> [any Automatable]) throws {
        self.homeManager = homeManager
        self.runs = runs
        self.getAutomations = getAutomations
    }

    public func trigger(with event: HomeEvent) async {
        let automations = await getAutomations()

        await withDiscardingTaskGroup { group in
            for automation in automations where automation.isActive {
                group.addTask {
                    do {
                        guard try await automation.shouldTrigger(with: event, using: self.homeManager) else {
                            return
                        }

                        self.log.info("Running automation \(automation.name)")
                        let run = await self.startRun(of: automation, for: event)
                        let task = Task {
                            do {
                                try await AutomationRunContext.$runId.withValue(run?.id) {
                                    try await automation.execute(using: self.homeManager)
                                }
                                await self.finish(run, outcome: .completed)
                            } catch is CancellationError {
                                let stopped = await self.consumeStopRequest(for: automation.name)
                                await self.finish(run, outcome: stopped ? .stopped : .superseded)
                            } catch {
                                self.log.error("Automation failed with error - \(error)")
                                await self.finish(run, outcome: .failed, error: String(describing: error))
                            }

                            // cancel the current task after completion to get correct results of getActiveAutomationNames
                            withUnsafeCurrentTask { currentTask in
                                currentTask?.cancel()
                            }
                        }
                        await self.set(task: task, with: automation.name)
                    } catch {
                        self.log.error("Automation shouldTrigger failed with error - \(error)")
                    }
                }
            }
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

    private func startRun(of automation: any Automatable, for event: HomeEvent) async -> AutomationRun? {
        guard automation.recordsRuns else { return nil }

        var trigger = event.trigger
        if let detail = await automation.triggerSummary(for: event, using: homeManager) {
            trigger = trigger.appending(detail)
        }
        let run = AutomationRun(automationName: automation.name, startedAt: Date(), trigger: trigger, outcome: .running)
        do {
            try await runs.add(run)
            return run
        } catch {
            log.error("Failed to record automation run - \(error)")
            return nil
        }
    }

    private func finish(_ run: AutomationRun?, outcome: AutomationRun.Outcome, error: String? = nil) async {
        guard let run else { return }
        do {
            try await runs.finish(run.id, outcome: outcome, endedAt: Date(), errorDescription: error)
        } catch {
            log.error("Failed to finish automation run - \(error)")
        }
    }
}
