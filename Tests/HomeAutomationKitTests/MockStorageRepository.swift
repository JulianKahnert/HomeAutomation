//
//  MockStorageRepository.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 29.07.24.
//

import Foundation
import HAModels

final class MockStorageRepository: StorageRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var storedItems: [EntityStorageItem]

    /// The persist task of a HomeManager appends while a test or a read looks, so every access takes the lock.
    var items: [EntityStorageItem] {
        get { lock.withLock { storedItems } }
        set { lock.withLock { storedItems = newValue } }
    }

    init(items: [EntityStorageItem] = []) {
        self.storedItems = items
    }

    func getCurrent(_ entityId: EntityId) async throws -> EntityStorageItem? {
        return items.last { $0.entityId == entityId }
    }

    func getPrevious(_ entityId: EntityId) async throws -> EntityStorageItem? {
        return nil
    }

    func getAllCurrent() async throws -> [EntityStorageItem] {
        Array(Dictionary(items.map { ($0.entityId, $0) }, uniquingKeysWith: { _, newer in newer }).values)
    }

    func add(_ item: EntityStorageItem) async throws {
        lock.withLock { storedItems.append(item) }
    }

    func getHistory(
        for entityId: EntityId,
        startDate: Date?,
        endDate: Date?,
        cursor: Date?,
        limit: Int
    ) async throws -> [EntityStorageItem] {
        var filtered = items.filter { $0.entityId == entityId }

        if let startDate {
            filtered = filtered.filter { $0.timestamp >= startDate }
        }

        if let endDate {
            filtered = filtered.filter { $0.timestamp < endDate }
        }

        if let cursor {
            filtered = filtered.filter { $0.timestamp < cursor }
        }

        return Array(filtered.sorted { $0.timestamp > $1.timestamp }.prefix(limit))
    }

    func getAllEntityIds() async throws -> [EntityId] {
        var seen = Set<EntityId>()
        var uniqueEntityIds: [EntityId] = []

        for item in items where !seen.contains(item.entityId) {
            seen.insert(item.entityId)
            uniqueEntityIds.append(item.entityId)
        }

        return uniqueEntityIds
    }
}
