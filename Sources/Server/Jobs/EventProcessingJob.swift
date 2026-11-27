//
//  EventProcessingJob.swift
//  HomeAutomationServer
//
//  Created by Julian Kahnert on 16.02.25.
//

import Foundation
import HAApplicationLayer
import HAModels
import Logging
import Shared

/// How long the event loop has been on its current event, for `/health`.
actor EventLoopGauge {
    private var startedAt: Date?

    func began(at date: Date = Date()) { startedAt = date }
    func ended() { startedAt = nil }
    func age(now: Date = Date()) -> TimeInterval {
        startedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
    }
}

struct HomeEventProcessingJob: Job, Log {
    let gauge: EventLoopGauge
    let homeEventsStream: AsyncStream<HomeEvent>
    let automationService: AutomationService
    let homeManager: any HomeManagable

    func run() async {
        // Serial processing preserves event ordering (history writes and automation triggering).
        // `trigger(with:)` returns quickly — long-running `execute()` runs in the background inside
        // AutomationService — so a slow automation does not stall the loop.
        for await event in homeEventsStream {
            await gauge.began()
            await handle(event)
            await gauge.ended()
        }
    }

    private func handle(_ event: HomeEvent) async {
        log.debug("trigger automation with \(event.description)")

        // add item to history
        if case .change(let item) = event {
            // A value-identical replay carries no new information: the adapter re-yields its
            // full entity state on every rescan (reconnect resync, reachability flap), and
            // triggering on those would supersede running automations for nothing.
            // A server-owned state was checked and set when it was reported; checking it again would find it equal.
            if !item.origin.isCheckedAtSource {
                guard await homeManager.addEntityHistory(item) else { return }
            }
        }

        // hand the event to the lane of every active automation
        await automationService.trigger(with: event)
    }
}
