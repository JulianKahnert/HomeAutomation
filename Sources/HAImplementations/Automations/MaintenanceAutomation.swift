//
//  MaintenanceAutomation.swift
//
//
//  Created by Julian Kahnert on 01.07.24.
//

import Foundation
import HAModels

public struct MaintenanceAutomation: Automatable {
    public var isActive = true
    public let name: String
    public private(set) var triggerEntityIds = Set<EntityId>()
    public let time: Time
    public var recordsRuns: Bool { false }

    public init(_ name: String, at time: Time) {
        self.name = name
        self.time = time
    }

    public func shouldTrigger(with event: HomeEvent, using hm: HomeManagable) async throws -> Bool {
        return time.isEqual(event)
    }

    // Retention lives in the server's `DatabaseCleanupJob` only; the type stays so existing
    // configs still decode.
    public func execute(using hm: HomeManagable) async throws {}
}
