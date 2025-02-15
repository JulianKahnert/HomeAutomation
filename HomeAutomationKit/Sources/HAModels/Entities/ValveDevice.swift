//
//  ValveDevice.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 13.02.25.
//

open class ValveDevice: Codable, @unchecked Sendable, Validatable, Log {
    public let valveId: EntityId

    public init(valveId: EntityId) {
        self.valveId = valveId
    }

    public func turn(on active: Bool, with hm: HomeManagable) async {
        await hm.perform(.setValve(valveId, active: active))
    }

    public func validate(with hm: any HomeManagable) async throws {
        try await hm.findEntity(valveId)
    }
}
