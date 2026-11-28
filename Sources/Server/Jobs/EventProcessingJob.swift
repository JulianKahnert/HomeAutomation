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

/// Where everything that happens is yielded into the event stream; stamps each event and write for the ``EventLoopGauge``.
struct HomeEventSink: Sendable {
    let continuation: AsyncStream<HomeInput>.Continuation
    let gauge: EventLoopGauge

    func yield(_ event: HomeEvent) {
        yield(.event(event))
    }

    func yield(_ input: HomeInput) {
        gauge.stamp()
        continuation.yield(input)
    }
}

struct HomeEventProcessingJob: Job, Log {
    let gauge: EventLoopGauge
    let homeEventsStream: AsyncStream<HomeInput>
    let automationService: AutomationService
    let homeManager: any HomeManagable

    func run() async {
        // Serial processing preserves event ordering (history writes and automation triggering).
        // `trigger(with:)` returns quickly — long-running `execute()` runs in the background inside
        // AutomationService — so a slow automation does not stall the loop.
        for await input in homeEventsStream {
            gauge.took()
            switch input {
            case .event(let event): await handle(event)
            case .write(let command): await handle(command)
            }
            gauge.finished()
        }
    }

    /// Runs a write of the API in its turn and answers the caller. A command that only starts or cancels work
    /// (`stopAutomation` cancels a run, it does not wait for it or for its lane) never holds the loop.
    private func handle(_ command: WriteCommand) async {
        log.debug("Handle write", metadata: ["command": "\(command.kind.name)"])
        do {
            switch command.kind {
            case .setState(let entityId, let value):
                // The report sets the state at once and yields the change into this stream, already checked.
                let changed: Bool
                do {
                    changed = try await homeManager.report(entityId, value: value, origin: .app)
                } catch ReportError.valueDoesNotFit {
                    throw CoreCommandError.valueDoesNotFit(entityId)
                } catch ReportError.notServerOwned {
                    throw CoreCommandError.notSettable(entityId)
                }
                // The report just set it: a state that cannot be read back is a failure of the server, not of the request.
                guard let item = try? await homeManager.getCurrentEntity(with: entityId), item.value != nil else {
                    throw CoreCommandError.stateUnreadable(entityId)
                }
                command.complete(.success(StateChange(item: item, changed: changed)))
                return
            case .setAutomationActive(let name, let isActive):
                try await automationService.setAutomationActive(with: name, to: isActive)
            case .stopAutomation(let name):
                await automationService.stopAutomation(with: name)
            case .deploy(let automations, let location):
                try await automationService.deploy(automations, location: location)
                // After the config is stored, so automations that react see the new one.
                await automationService.trigger(with: .configDeployed)
            }
            command.complete(.success(nil))
        } catch {
            command.complete(.failure(error))
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
