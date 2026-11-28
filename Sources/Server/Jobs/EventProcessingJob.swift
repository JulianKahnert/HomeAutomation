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
import Synchronization

/// How long the oldest event the event loop has not finished has been on its way, for `/health`: an event is
/// stamped when it is yielded into the stream and counts until the loop has handled it, so the wait in the
/// stream shows as well as a slow event.
final class EventLoopGauge: Sendable {
    private struct State {
        var waiting: [Date] = []
        var handling: Date?
        var backlog = BacklogReporter()
    }

    private let state = Mutex(State())

    /// An event was yielded into the stream.
    func stamp(at date: Date = Date()) {
        state.withLock { $0.waiting.append(date) }
    }

    /// The loop took the oldest waiting event.
    func took() {
        state.withLock { state in
            guard !state.waiting.isEmpty else { return }
            state.handling = state.waiting.removeFirst()
        }
    }

    /// The loop is done with the event it took.
    func finished() {
        state.withLock { $0.handling = nil }
    }

    func age(now: Date = Date()) -> TimeInterval {
        state.withLock { Self.age(of: $0, now: now) }
    }

    /// The age to log critical when it is above `limit` and not reported yet; `nil` otherwise. The backlog is
    /// reported again only after it has drained.
    func reportsBacklog(olderThan limit: TimeInterval, now: Date = Date()) -> TimeInterval? {
        state.withLock { state in
            let age = Self.age(of: state, now: now)
            return state.backlog.report(age: age, olderThan: limit)
        }
    }

    private static func age(of state: State, now: Date) -> TimeInterval {
        BacklogReporter.age(ofOldest: state.handling ?? state.waiting.first, now: now)
    }
}

/// Where everything that happens is yielded into the event stream; stamps each event for the ``EventLoopGauge``.
struct HomeEventSink: Sendable {
    let continuation: AsyncStream<HomeEvent>.Continuation
    let gauge: EventLoopGauge

    func yield(_ event: HomeEvent) {
        gauge.stamp()
        continuation.yield(event)
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
            gauge.took()
            await handle(event)
            gauge.finished()
        }
    }

    private func handle(_ event: HomeEvent) async {
        log.debug("Trigger automation", metadata: ["event": "\(event.description)"])

        // add item to history
        if case .change(let item) = event {
            // A value-identical replay carries no new information: the adapter re-yields its
            // full entity state on every rescan (reconnect resync, reachability flap), and
            // triggering on those would supersede running automations for nothing.
            // A server-owned state was checked and set when it was reported (`HomeManagable.report`, whatever the
            // origin: app, server or a polling job); checking it again would find it equal and drop the event.
            if !(item.entityId.isServerOwned && item.origin != .homekit) {
                guard await homeManager.addEntityHistory(item) else { return }
            }
        }

        // hand the event to the lane of every active automation
        await automationService.trigger(with: event)
    }
}
