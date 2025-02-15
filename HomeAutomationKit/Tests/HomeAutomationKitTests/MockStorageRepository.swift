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
}
