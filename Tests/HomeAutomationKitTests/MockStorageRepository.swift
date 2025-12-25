//
//  MockStorageRepository.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 29.07.24.
//

import Foundation
import HAModels

final class MockStorageRepository: StorageRepository, @unchecked Sendable {
    var items: [EntityStorageItem]

    init(items: [EntityStorageItem] = []) {
        self.items = items
    }

    func getCurrent(_ entityId: EntityId) async throws -> EntityStorageItem? {
        return items.last { $0.entityId == entityId }
    }

    func getPrevious(_ entityId: EntityId) async throws -> EntityStorageItem? {
        return nil
    }

    func add(_ item: EntityStorageItem) async throws {
        items.append(item)
    }

    func deleteEntries(olderThan date: Date) async throws {
        fatalError()
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
            filtered = filtered.filter { $0.timestamp <= endDate }
        }

        if let cursor {
            filtered = filtered.filter { $0.timestamp < cursor }
        }

        return Array(filtered.sorted { $0.timestamp > $1.timestamp }.prefix(limit))
    }

    func getAllEntityIds() async throws -> [EntityId] {
        var seen = Set<EntityId>()
        var uniqueEntityIds: [EntityId] = []

        for item in items {
            if !seen.contains(item.entityId) {
                seen.insert(item.entityId)
                uniqueEntityIds.append(item.entityId)
            }
        }

        return uniqueEntityIds
    }
}
