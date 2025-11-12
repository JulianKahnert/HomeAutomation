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
        // This is where you would send the email
        for await event in homeEventsStream {
            log.debug("trigger automation with \(event.description)")

            // add item to history
            switch event {
            case .change(let item):
                await homeManager.addEntityHistory(item)
            case .time, .sunset, .sunrise:
                break
            }

            // perform automation
            await automationService.trigger(with: event)
        }
    }
}
