//
//  EntityHourlyAggregate.swift
//  HomeAutomationServer
//

import Foundation
import HAModels

/// One entity's values of one hour, condensed by the rollup job from raw `entityItems` rows that
/// fall inside the type's valid range. Key: entity and `hourStart` (UTC).
struct EntityHourlyAggregate: Sendable, Equatable {
    static let schema = "entityHourlyAggregates"

    let entityId: EntityId
    let hourStart: Date
    let minValue: Double
    let meanValue: Double
    let maxValue: Double
    /// Value of the newest raw row in the hour.
    let lastValue: Double
    let valueCount: Int
}

/// What the cleanup and rollup jobs need from the entity storage.
protocol EntityRetentionStore: Sendable {
    /// Deletes the raw rows of `type` older than `date`.
    func deleteEntries(ofType type: CharacteristicsType, olderThan date: Date) async throws

    /// Aggregates the raw rows of `type` older than `date` per entity and hour, then deletes them,
    /// in one transaction. Values outside `validRange` are dropped.
    func rollUpHourly(type: CharacteristicsType, column: StoragePolicy.ValueColumn, validRange: ClosedRange<Double>?, olderThan date: Date) async throws

    /// Entities with more than `limit` rows since `date`. Types stay strings, so a type this server
    /// version does not know is counted too.
    func entitiesWithRowCount(above limit: Int, since date: Date) async throws -> [EntityRowCount]
}

struct EntityRowCount: Sendable, Equatable {
    let placeId: String
    let serviceName: String
    let characteristicType: String
    let rows: Int
}
