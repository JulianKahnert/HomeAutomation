//
//  StorageUpkeep.swift
//  HAModels
//

import Foundation

/// One piece of upkeep of the server's database. A further cleanup (e.g. old journal entries) is a new
/// case here plus its branch in the server's ``StorageUpkeep``; the automation and the facade stay as they are.
public enum StorageUpkeepStep: String, Sendable, CaseIterable, Codable {
    /// Deletes what is past its retention (raw rows, old automation runs) and warns about noisy entities.
    case cleanup
    /// Condenses old raw rows into hourly aggregates.
    case rollup
}

/// What the server's database does for ``StorageUpkeepStep``s; reached through ``HomeManagable/performStorageUpkeep(_:now:)``.
public protocol StorageUpkeep: Sendable {
    func perform(_ step: StorageUpkeepStep, now: Date) async throws
}
