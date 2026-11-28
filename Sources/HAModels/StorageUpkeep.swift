//
//  StorageUpkeep.swift
//  HAModels
//

import Foundation

/// One piece of upkeep of the server's database. A further cleanup is a new case here plus its branch in the server's ``StorageUpkeep``; the automation and the facade stay as they are.
public enum StorageUpkeepStep: String, Sendable, CaseIterable, Codable {
    /// Deletes raw rows past their retention and warns about noisy entities.
    case cleanup
    /// Condenses old raw rows into hourly aggregates.
    case rollup
    /// Deletes journal entries (runs, commands, pushes) past their retention.
    case journal
}

/// What the server's database does for ``StorageUpkeepStep``s; reached through ``HomeManagable/performStorageUpkeep(_:now:)``.
public protocol StorageUpkeep: Sendable {
    func perform(_ step: StorageUpkeepStep, now: Date) async throws
}
