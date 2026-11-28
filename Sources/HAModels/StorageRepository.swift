//
//  StorageRepository.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 23.07.24.
//

import Foundation

public protocol StorageRepository: Sendable {
    func getCurrent(_ entityId: EntityId) async throws -> EntityStorageItem?
    /// The last stored state of every entity, in one query; the server loads it once at start.
    func getAllCurrent() async throws -> [EntityStorageItem]

    /// Like ``getAllCurrent()``, for the entities of one characteristic type only.
    func getAllCurrent(of type: CharacteristicsType) async throws -> [EntityStorageItem]

    func add(_ item: EntityStorageItem) async throws

    /// Query entity history with cursor-based pagination
    /// - Parameters:
    ///   - entityId: The entity to query history for
    ///   - startDate: Optional start date for the time range (inclusive)
    ///   - endDate: Optional end date for the time range (exclusive)
    ///   - cursor: Optional cursor timestamp for pagination (fetch items older than this)
    ///   - limit: Maximum number of items to return (default 100)
    /// - Returns: Array of historical entity storage items, ordered by timestamp descending
    func getHistory(
        for entityId: EntityId,
        startDate: Date?,
        endDate: Date?,
        cursor: Date?,
        limit: Int
    ) async throws -> [EntityStorageItem]

    /// Stores when the entity last reported, a change included. The home manager throttles it to one write per entity
    /// and five minutes; the readers of the current state return the later of it and the newest change's timestamp.
    /// The time only moves forward.
    func recordLastReport(of entityId: EntityId, at date: Date) async throws

    /// Get all unique entity IDs that have historical data
    /// - Returns: Array of unique EntityIds
    func getAllEntityIds() async throws -> [EntityId]
}

extension StorageRepository {
    public func getAllCurrent(of type: CharacteristicsType) async throws -> [EntityStorageItem] {
        try await getAllCurrent().filter { $0.entityId.characteristicType == type }
    }

    /// Like `getHistory`, but with `includePrevious` the last state before `startDate` is appended as
    /// the oldest item, so a state that began before the window is not lost. Only on the last page.
    public func getHistory(for entityId: EntityId, startDate: Date?, endDate: Date?, cursor: Date?, limit: Int, includePrevious: Bool) async throws -> [EntityStorageItem] {
        var items = try await getHistory(for: entityId, startDate: startDate, endDate: endDate, cursor: cursor, limit: limit)
        guard includePrevious, let startDate, items.count < limit,
              let previous = try await getHistory(for: entityId, startDate: nil, endDate: startDate, cursor: nil, limit: 1).first else {
            return items
        }
        items.append(previous)
        return items
    }

    /// History of every entity in `placeId`, at most 1000 items each, newest first.
    public func getRoomHistory(placeId: String, startDate: Date?, endDate: Date?, includePrevious: Bool) async throws -> [(entityId: EntityId, items: [EntityStorageItem])] {
        var result: [(entityId: EntityId, items: [EntityStorageItem])] = []
        for entityId in try await getAllEntityIds() where entityId.placeId == placeId {
            let items = try await getHistory(for: entityId, startDate: startDate, endDate: endDate, cursor: nil, limit: 1000, includePrevious: includePrevious)
            result.append((entityId, items))
        }
        return result
    }
}
