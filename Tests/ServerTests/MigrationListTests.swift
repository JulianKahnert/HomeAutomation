//
//  MigrationListTests.swift
//  HomeAutomationServer
//

import Fluent
@testable import Server
import Testing

struct MigrationListTests {
    @Test("A new database starts from exactly one migration")
    func listHoldsOneMigration() {
        #expect(ServerMigrations.all.count == 1)
    }
}
