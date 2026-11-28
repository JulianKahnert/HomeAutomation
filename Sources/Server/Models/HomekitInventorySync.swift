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

    /// Refreshes on every element of `handshakes` and every `refreshInterval`, until the task is cancelled.
    func run(handshakes: AsyncStream<Void>, interval: Duration = Self.refreshInterval) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                // Right at the start, when the adapter is already connected; otherwise its first connect triggers it.
                await refresh()
                for await _ in handshakes {
                    await refresh()
                }
            }
            group.addTask {
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: interval)
                    } catch {
                        return
                    }
                    await refresh()
                }
            }
            await group.waitForAll()
        }
    }
}

/// Cancels a background task when the application shuts down.
struct CancelOnShutdown: LifecycleHandler {
    let task: Task<Void, Never>

    func shutdown(_ application: Application) {
        task.cancel()
    }
}
