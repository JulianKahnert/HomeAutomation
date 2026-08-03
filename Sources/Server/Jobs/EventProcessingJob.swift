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
                // A value-identical replay carries no new information: the adapter re-yields its
                // full entity state on every rescan (reconnect resync, reachability flap), and
                // triggering on those would supersede running automations for nothing.
                guard await homeManager.addEntityHistory(item) else { continue }
            }

            // perform automation
            await automationService.trigger(with: event)
        }
    }
}
