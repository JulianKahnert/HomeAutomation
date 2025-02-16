//
//  HealthCheck.swift
//
//
//  Created by Julian Kahnert on 01.07.24.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
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
        let (data, _) = try await URLSession.shared.data(from: url)
        log.debug("Healthcheck response: \(String(data: data, encoding: .utf8) ?? "")")
    }
}
