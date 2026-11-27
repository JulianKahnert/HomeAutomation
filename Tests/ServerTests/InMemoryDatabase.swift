//
//  InMemoryDatabase.swift
//  HomeAutomationServer
//

import Fluent
import Foundation
import SQLKit
import Synchronization
import XCTVapor

/// Answers every Fluent read with the rows of its table (filters, sorting and limits ignored), appends every
/// created row to its table and answers every raw SQL statement with no rows, so the routes run without MySQL.
/// Updates and deletes change nothing.
struct InMemoryDatabaseConfiguration: DatabaseConfiguration {
    var middleware: [any AnyModelMiddleware] = []
    let tables: InMemoryTables

    init(rows: [String: [[String: any Sendable]]] = [:]) {
        tables = InMemoryTables(rows: rows)
    }

    func makeDriver(for databases: Databases) -> any DatabaseDriver {
        InMemoryDriver(tables: tables)
    }
}

/// The rows of every table, shared by all connections of one configuration.
final class InMemoryTables: Sendable {
    private let rows: Mutex<[String: [[String: any Sendable]]]>

    init(rows: [String: [[String: any Sendable]]]) {
        self.rows = Mutex(rows)
    }

    func rows(of table: String) -> [[String: any Sendable]] {
        rows.withLock { $0[table] ?? [] }
    }

    func append(_ row: [String: any Sendable], to table: String) {
        rows.withLock { $0[table, default: []].append(row) }
    }
}

private struct InMemoryDriver: DatabaseDriver {
    let tables: InMemoryTables

    func makeDatabase(with context: DatabaseContext) -> any Database {
        InMemoryDatabase(context: context, tables: tables)
    }

    func shutdown() {}
}

private struct InMemoryDatabase: Database, SQLDatabase {
    let context: DatabaseContext
    let tables: InMemoryTables

    var logger: Logger { context.logger }
    var eventLoop: any EventLoop { context.eventLoop }
    var dialect: any SQLDialect { InMemoryDialect() }
    var inTransaction: Bool { false }

    func execute(query: DatabaseQuery, onOutput: @escaping @Sendable (any DatabaseOutput) -> Void) -> EventLoopFuture<Void> {
        let outputs: [[String: any Sendable]]
        switch query.action {
        case .create:
            // Fluent waits for one output per created row.
            outputs = query.input.compactMap { input in
                guard case .dictionary(let values) = input else { return nil }
                var row: [String: any Sendable] = [:]
                for (key, value) in values {
                    if case .bind(let bound) = value { row[key.description] = bound }
                }
                tables.append(row, to: query.schema)
                return row
            }
        case .read:
            outputs = tables.rows(of: query.schema)
        default:
            outputs = []
        }
        // Fluent expects every output on the event loop.
        return eventLoop.submit {
            for row in outputs {
                onOutput(InMemoryOutput(values: row))
            }
        }
    }

    func execute(schema: DatabaseSchema) -> EventLoopFuture<Void> { eventLoop.makeSucceededVoidFuture() }
    func execute(enum: DatabaseEnum) -> EventLoopFuture<Void> { eventLoop.makeSucceededVoidFuture() }

    func execute(sql query: any SQLExpression, _ onRow: @escaping @Sendable (any SQLRow) -> Void) -> EventLoopFuture<Void> {
        eventLoop.makeSucceededVoidFuture()
    }

    func transaction<T>(_ closure: @escaping @Sendable (any Database) -> EventLoopFuture<T>) -> EventLoopFuture<T> { closure(self) }
    func withConnection<T>(_ closure: @escaping @Sendable (any Database) -> EventLoopFuture<T>) -> EventLoopFuture<T> { closure(self) }
}

private struct InMemoryDialect: SQLDialect {
    var name: String { "in-memory" }
    var identifierQuote: any SQLExpression { SQLRaw("`") }
    var supportsAutoIncrement: Bool { false }
    var autoIncrementClause: any SQLExpression { SQLRaw("") }
    func bindPlaceholder(at position: Int) -> any SQLExpression { SQLRaw("?") }
    func literalBoolean(_ value: Bool) -> any SQLExpression { SQLRaw(value ? "1" : "0") }
}

private struct InMemoryOutput: DatabaseOutput {
    let values: [String: any Sendable]

    var description: String { "\(values)" }

    func schema(_ schema: String) -> any DatabaseOutput { self }

    func contains(_ key: FieldKey) -> Bool { values[key.description] != nil }

    func decodeNil(_ key: FieldKey) throws -> Bool {
        guard let value = values[key.description] else { return true }
        let mirror = Mirror(reflecting: value)
        return mirror.displayStyle == .optional && mirror.children.isEmpty
    }

    func decode<T: Decodable>(_ key: FieldKey, as type: T.Type) throws -> T {
        guard let value = values[key.description] as? T else {
            throw DecodingError.typeMismatch(T.self, .init(codingPath: [], debugDescription: "no \(T.self) at \(key)"))
        }
        return value
    }
}
