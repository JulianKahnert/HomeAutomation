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
        // Serial processing preserves event ordering (history writes and automation triggering).
        // `trigger(with:)` returns quickly — long-running `execute()` runs in the background inside
        // AutomationService — so a slow automation does not stall the loop.
        for await event in homeEventsStream {
            log.debug("trigger automation with \(event.description)")

            // add item to history
            if case .change(let item) = event {
                await homeManager.addEntityHistory(item)
            }

            // perform automation
            await automationService.trigger(with: event)
        }
    }
}
