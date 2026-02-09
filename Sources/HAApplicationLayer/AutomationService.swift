//
//  AutomationService.swift
//  
//
//  Created by Julian Kahnert on 01.07.24.
//

import HAModels
import Logging

public actor AutomationService {
    private let log = Logger(label: "AutomationManager")
    private let homeManager: HomeManagable
    private let getAutomations: () async -> [any Automatable]
    private var runningTasks: [String: Task<Void, Never>] = [:]

    public init(using homeManager: HomeManagable, getAutomations: @escaping () async -> [any Automatable]) throws {
        self.homeManager = homeManager
        self.getAutomations = getAutomations
    }

    public func trigger(with event: HomeEvent) async {
        let automations = await getAutomations()

        await withTaskGroup(of: Void.self) { group in
            for automation in automations where automation.isActive {
                group.addTask {
                    do {
                        guard try await automation.shouldTrigger(with: event, using: self.homeManager) else {
                            return
                        }

                        self.log.info("Running automation \(automation.name)")
                        let task = Task { [weak self] in
                            guard let self else { return }
                            do {
                                try await automation.execute(using: self.homeManager)
                            } catch is CancellationError {
                                // do not throw anything when an automation was cancelled
                            } catch {
                                self.log.critical("Automation failed with error - \(error)")
                            }

                            // cancel the current task after completion to get correct results of getActiveAutomationNames
                            withUnsafeCurrentTask { currentTask in
                                currentTask?.cancel()
                            }
                        }
                        await self.set(task: task, with: automation.name)
                    } catch {
                        self.log.critical("Automation (e.g. shouldTrigger failed with error - \(error)")
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
        runningTasks[name]?.cancel()
    }

    private func set(task: Task<Void, Never>, with id: String) {
        if let runningTask = runningTasks[id],
           !runningTask.isCancelled {
            runningTask.cancel()
        }

        runningTasks[id] = task
    }
}
