//
//  ReadSideFixtures.swift
//  HomeAutomationServer
//

import Foundation
import HAApplicationLayer
@testable import HAImplementations
import HAModels
import Shared
@testable import Server
import XCTVapor

/// A storage that keeps what it is given and answers like the database does: the newest change is the current state,
/// the history is newest first. Lets the read routes run without MySQL and without a core.
actor MemoryStorage: StorageRepository {
    private var changes: [EntityId: [EntityStorageItem]] = [:]
    private var lastReports: [EntityId: Date] = [:]
    private var added = 0
    /// The entities in the order their changes were stored.
    private(set) var addedIds: [EntityId] = []
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(seed: [EntityStorageItem] = []) {
        for item in seed.sorted(by: { $0.timestamp < $1.timestamp }) {
            changes[item.entityId, default: []].append(item)
            if let lastReport = item.lastReport { lastReports[item.entityId] = lastReport }
        }
    }

    func getCurrent(_ entityId: EntityId) async throws -> EntityStorageItem? {
        guard var item = changes[entityId]?.last else { return nil }
        item.lastReport = lastReports[entityId] ?? item.lastReport
        return item
    }

    func getAllCurrent() async throws -> [EntityStorageItem] {
        var items: [EntityStorageItem] = []
        for entityId in changes.keys {
            if let item = try await getCurrent(entityId) { items.append(item) }
        }
        return items
    }

    func add(_ item: EntityStorageItem) async throws {
        var stored = item
        stored.lastReport = nil
        changes[item.entityId, default: []].append(stored)
        if let lastReport = item.lastReport { lastReports[item.entityId] = lastReport }
        added += 1
        addedIds.append(item.entityId)
        let ready = waiters.filter { $0.count <= added }
        waiters.removeAll { $0.count <= added }
        for waiter in ready { waiter.continuation.resume() }
    }

    func recordLastReport(of entityId: EntityId, at date: Date) async throws {
        lastReports[entityId] = date
    }

    func getHistory(for entityId: EntityId, startDate: Date?, endDate: Date?, cursor: Date?, limit: Int) async throws -> [EntityStorageItem] {
        let items = (changes[entityId] ?? []).filter { item in
            (startDate.map { item.timestamp >= $0 } ?? true) && (endDate.map { item.timestamp < $0 } ?? true) && (cursor.map { item.timestamp < $0 } ?? true)
        }
        return Array(items.sorted { $0.timestamp > $1.timestamp }.prefix(limit))
    }

    func getAllEntityIds() async throws -> [EntityId] { Array(changes.keys) }

    /// Returns once `count` changes were added, without polling; fails the test after `timeout` instead of hanging.
    func waitForChanges(_ count: Int, timeout: Duration = .seconds(10), file: StaticString = #filePath, line: UInt = #line) async {
        guard added < count else { return }
        do {
            try await raceTimeout(timeout, timeoutError: { TestWaitTimeout() }) { await self.registerWaiter(count) }
        } catch {
            XCTFail("Fewer than \(count) changes were added within \(timeout)", file: file, line: line)
        }
    }

    private func registerWaiter(_ count: Int) async {
        guard added < count else { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
}

/// A configuration that is stored already.
struct StoredConfig: ConfigReading {
    let config: ConfigDTO

    func load() async throws -> ConfigDTO { config }
}

extension Application {
    /// Wires the event loop to a stream of its own and runs it; the returned task ends it. The `HomeManager` and
    /// `AutomationService` must be set before.
    func startEventLoop() -> Task<Void, Never> {
        let (stream, continuation) = AsyncStream.makeStream(of: HomeInput.self)
        homeEventsStream = stream
        homeEventsContinuation = continuation
        let job = HomeEventProcessingJob(gauge: eventLoopGauge, homeEventsStream: stream,
                                         automationService: automationService, homeManager: homeManager)
        return Task { await job.run() }
    }
}

/// A wait in a test that did not end in time.
struct TestWaitTimeout: Error {}
