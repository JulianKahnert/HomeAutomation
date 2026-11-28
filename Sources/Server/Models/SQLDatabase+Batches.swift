//
//  SQLDatabase+Batches.swift
//  HomeAutomationServer
//

import SQLKit

extension SQLDatabase {
    /// Deletes the rows of `table` that match `filter`, oldest `timestamp` first, in statements of at most `batchSize`
    /// rows: a statement locks only its batch, and a large backlog does not become one transaction. The filter is
    /// written once and used for the delete and for the probe that ends the loop, so the two cannot differ. A stop
    /// ends it between two batches.
    func deleteInBatches(from table: String, where filter: SQLQueryString, batchSize: Int) async throws {
        while true {
            try Task.checkCancellation()
            try await raw("""
                DELETE FROM \(ident: table) WHERE \(filter)
                ORDER BY \(ident: "timestamp") LIMIT \(literal: batchSize)
                """)
                .run()
            let left = try await raw("SELECT 1 AS \(ident: "found") FROM \(ident: table) WHERE \(filter) LIMIT 1").first()
            if left == nil { return }
        }
    }
}
