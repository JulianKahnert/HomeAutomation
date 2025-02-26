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
                        let task = Task {
                            do {
                                try await automation.execute(using: self.homeManager)
                            } catch is CancellationError {
                                // do not throw anything when an automation was cancelled
                            } catch {
                                self.log.critical("Automation failed with error - \(error)")
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
        Set(runningTasks.keys)
    }

    private func set(task: Task<Void, Never>, with id: String) {
        if let runningTask = runningTasks[id],
           !runningTask.isCancelled {
            runningTask.cancel()
        }

        runningTasks[id] = task
    }
}
