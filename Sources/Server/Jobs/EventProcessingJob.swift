//
//  EventProcessingJob.swift
//  HomeAutomationServer
//
//  Created by Julian Kahnert on 16.02.25.
//

import HAApplicationLayer
import HAModels
import Logging
import Shared

struct HomeEventProcessingJob: Job, Log {
    let homeEventsStream: AsyncStream<HomeEvent>
    let automationService: AutomationService
    let homeManager: any HomeManagable

    func run() async {
        await withDiscardingTaskGroup { group in
            for await event in homeEventsStream {
                log.debug("trigger automation with \(event.description)")
                group.addTask {
                    if case .change(let item) = event {
                        await self.homeManager.addEntityHistory(item)
                    }
                    await self.automationService.trigger(with: event)
                }
            }
        }
    }
}
