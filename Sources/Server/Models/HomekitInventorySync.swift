//
//  HomekitInventorySync.swift
//  HomeAutomationServer
//

import Foundation
import HAModels
import Logging
import Vapor

/// Pulls the HomeKit inventory from the adapter and replaces the stored one: after each adapter connect and once a day
/// while connected (HomeKit's homes change rarely, and a day old is fresh enough for the questions it answers).
struct HomekitInventorySync: Sendable {
    static let refreshInterval: Duration = .seconds(24 * 3600)

    private let log = Logger(label: "HomekitInventorySync")
    /// Asks the adapter; `nil` while it is not connected.
    let fetch: @Sendable () async throws -> HomeKitInventory?
    let store: @Sendable (HomeKitInventory, Date) async throws -> Void
    let now: @Sendable () -> Date

    init(fetch: @escaping @Sendable () async throws -> HomeKitInventory?,
         store: @escaping @Sendable (HomeKitInventory, Date) async throws -> Void,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.fetch = fetch
        self.store = store
        self.now = now
    }

    /// One pull and one replace. A failure is logged and leaves the stored inventory as it was.
    @discardableResult
    func refresh() async -> Bool {
        let start = ContinuousClock.now
        do {
            guard let inventory = try await fetch() else {
                log.debug("HomeKit inventory not refreshed: adapter not connected")
                return false
            }
            try await store(inventory, now())
            log.info("HomeKit inventory: \(inventory.summary) in \(start.duration(to: .now))")
            for line in inventory.accessoryLines {
                log.debug("HomeKit inventory: \(line)")
            }
            return true
        } catch {
            log.warning("HomeKit inventory not refreshed", metadata: ["error": "\(error)"])
            return false
        }
    }

    /// Refreshes on every element of `handshakes` and every `interval`, until the task is cancelled. One loop does all
    /// refreshes, so they never overlap; triggers that arrive while one runs collapse into one more (an adapter that
    /// keeps reconnecting queues at most one). The first handshake after the server's start is the start-up fetch:
    /// the adapter is never connected before the server listens.
    func run(handshakes: AsyncStream<Void>, interval: Duration = Self.refreshInterval) async {
        let (triggers, trigger) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await _ in handshakes {
                    trigger.yield()
                }
            }
            group.addTask {
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: interval)
                    } catch {
                        return
                    }
                    trigger.yield()
                }
            }
            group.addTask {
                for await _ in triggers {
                    await refresh()
                }
            }
            // The first child that ends (cancellation) ends the others; the consumer ends once `triggers` finishes.
            await group.next()
            group.cancelAll()
            trigger.finish()
            await group.waitForAll()
        }
    }
}

/// Cancels a background task when the application shuts down and waits until it has ended, so a running
/// database write is over before the connection pool closes.
struct CancelOnShutdown: LifecycleHandler {
    let task: Task<Void, Never>

    func shutdownAsync(_ application: Application) async {
        task.cancel()
        await task.value
    }
}
