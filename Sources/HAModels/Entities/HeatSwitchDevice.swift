//
//  HeatSwitchDevice.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 13.02.25.
//

import Shared

open class HeatSwitchDevice: Codable, @unchecked Sendable, Validatable, Log {
    public let heatSwitchId: EntityId

    public init(heatSwitchId: EntityId) {
        self.heatSwitchId = heatSwitchId
    }

    public func turn(on active: Bool, with hm: HomeManagable) async {
        await hm.perform(.setHeating(heatSwitchId, active: active))
    }

    public func validate(with hm: any EntityValidator) async throws {
        try await hm.findEntity(heatSwitchId)
    }
}
