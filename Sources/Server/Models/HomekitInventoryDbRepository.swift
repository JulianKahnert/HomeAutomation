//
//  HomekitInventoryDbRepository.swift
//  HomeAutomationServer
//

import Fluent
import Foundation
import HAModels

/// The HomeKit inventory in the database: a snapshot of the adapter replaces the old one as a whole.
struct HomekitInventoryDbRepository: Sendable {
    /// Resolved per query, see `EntityStorageDbRepository.database`.
    let database: @Sendable () -> any Database

    /// Deletes every row and inserts `items`, in one transaction: a reader sees the old or the new snapshot, never a mix.
    func replace(with inventory: HomeKitInventory, syncedAt: Date) async throws {
        let rows = inventory.rows.map { HomekitInventoryDbItem($0, syncedAt: syncedAt) }
        try await database().transaction { transaction in
            try await HomekitInventoryDbItem.query(on: transaction).delete()
            for chunk in stride(from: 0, to: rows.count, by: 500).map({ Array(rows[$0 ..< min($0 + 500, rows.count)]) }) {
                try await chunk.create(on: transaction)
            }
        }
    }

    func all() async throws -> [HomekitInventoryDbItem] {
        try await HomekitInventoryDbItem.query(on: database()).sort(\.$id).all()
    }
}
