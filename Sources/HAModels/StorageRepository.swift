//
//  StorageRepository.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 23.07.24.
//

import Foundation

public protocol StorageRepository: Sendable {
    func getCurrent(_ entityId: EntityId) async throws -> EntityStorageItem?
    func getPrevious(_ entityId: EntityId) async throws -> EntityStorageItem?

    func add(_ item: EntityStorageItem) async throws
    func deleteEntries(olderThan date: Date) async throws

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

    /// Get all unique entity IDs that have historical data
    /// - Returns: Array of unique EntityIds
    func getAllEntityIds() async throws -> [EntityId]
}
