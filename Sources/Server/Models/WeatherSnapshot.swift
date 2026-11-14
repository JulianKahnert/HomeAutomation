//
//  WeatherSnapshot.swift
//  HomeAutomationServer
//

import Fluent
import Foundation

/// The complete raw weather response of one hourly fetch, kept as received so later analysis can use every variable.
/// Not touched by `DatabaseCleanupJob`: these rows are kept on purpose.
final class WeatherSnapshot: Model, @unchecked Sendable {
    static let schema = "weatherSnapshots"

    @ID(key: .id)
    var id: UUID?

    /// `latitude,longitude` as sent to the weather service.
    @Field(key: "locationKey")
    var locationKey: String

    @Field(key: "fetchedAt")
    var fetchedAt: Date

    /// Raw JSON response (LONGTEXT).
    @Field(key: "json")
    var json: String

    init() { }

    init(locationKey: String, fetchedAt: Date, json: String) {
        self.locationKey = locationKey
        self.fetchedAt = fetchedAt
        self.json = json
    }
}

protocol WeatherSnapshotStoring: Sendable {
    func add(locationKey: String, fetchedAt: Date, json: String) async throws
}

struct WeatherSnapshotDbRepository: WeatherSnapshotStoring {
    let database: @Sendable () -> any Database

    func add(locationKey: String, fetchedAt: Date, json: String) async throws {
        try await WeatherSnapshot(locationKey: locationKey, fetchedAt: fetchedAt, json: json).save(on: database())
    }
}
