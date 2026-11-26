//
//  FireplaceSwitchDbItem.swift
//  HomeAutomationServer
//

import Fluent
import Foundation
import HAModels

/// One switch of the fireplace mode (glossary: fireplace mode); the newest row is the current state.
final class FireplaceSwitchDbItem: Model, @unchecked Sendable {
    static let schema = "fireplaceSwitches"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "timestamp")
    var timestamp: Date

    @Field(key: "isOn")
    var isOn: Bool

    init() { }

    init(_ fireplaceSwitch: FireplaceSwitch) {
        timestamp = fireplaceSwitch.timestamp
        isOn = fireplaceSwitch.isOn
    }

    var fireplaceSwitch: FireplaceSwitch {
        FireplaceSwitch(timestamp: timestamp, isOn: isOn)
    }
}

struct FireplaceSwitchDbRepository: FireplaceRepository {
    /// Resolved per query, see `EntityStorageDbRepository.database`.
    let database: @Sendable () -> any Database

    func add(_ fireplaceSwitch: FireplaceSwitch) async throws {
        try await FireplaceSwitchDbItem(fireplaceSwitch).create(on: database())
    }

    func latest() async throws -> FireplaceSwitch? {
        try await FireplaceSwitchDbItem.query(on: database())
            .sort(\.$timestamp, .descending)
            .first()?
            .fireplaceSwitch
    }

    func switches(from startDate: Date, to endDate: Date) async throws -> [FireplaceSwitch] {
        let inRange = try await FireplaceSwitchDbItem.query(on: database())
            .filter(\.$timestamp >= startDate)
            .filter(\.$timestamp < endDate)
            .sort(\.$timestamp, .ascending)
            .all()
        let before = try await FireplaceSwitchDbItem.query(on: database())
            .filter(\.$timestamp < startDate)
            .sort(\.$timestamp, .descending)
            .first()
        return ((before.map { [$0] } ?? []) + inRange).map(\.fireplaceSwitch)
    }
}
