//
//  HealthCheck.swift
//
//
//  Created by Julian Kahnert on 01.07.24.
//

import Foundation
import HAModels

public struct HealthCheck: Automatable {
    public let name: String
    public let url: URL
    public var triggerEntityIds = Set<EntityId>()

    public init(_ name: String, url: URL) {
        self.name = name
        self.url = url
    }

    public func shouldTrigger(with event: HomeEvent, using hm: HomeManagable) async throws -> Bool {
        guard case HomeEvent.time(_) = event else {
            return false
        }

        return true
    }

    public func execute(using hm: HomeManagable) async throws {
        let data = try Data(contentsOf: url)
        log.debug("Healthcheck response: \(String(data: data, encoding: .utf8) ?? "")")
    }
}
