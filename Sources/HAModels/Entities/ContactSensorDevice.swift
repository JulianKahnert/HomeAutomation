//
//  ContactSensorDevice.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 13.02.25.
//

import Foundation
import Shared

open class ContactSensorDevice: Codable, @unchecked Sendable, Validatable, Log {
    public let contactSensorId: EntityId
    public let batterySensorId: EntityId?

    public init(contactSensorId: EntityId, batterySensorId: EntityId?) {
        self.contactSensorId = contactSensorId
        self.batterySensorId = batterySensorId
    }

    public func isContactOpen(with hm: HomeManagable) async throws -> Bool {
        let item = try await hm.getCurrentEntity(with: contactSensorId)
        return try item.isContactOpen.get(with: log)
    }

    func getStateOfCharge(with hm: HomeManagable) async throws -> Int {
        let batterySensorId = try batterySensorId.get(with: log)
        let item = try await hm.getCurrentEntity(with: batterySensorId)
        return try item.stateOfCharge.get(with: log)
    }

    public func validate(with hm: any EntityValidator) async throws {

        try await hm.findEntity(contactSensorId)
        if let batterySensorId {
            do {
                try await hm.findEntity(batterySensorId)
            } catch {
                log.warning("Failed to get battery sensor for \(batterySensorId)")
            }
        }
    }
}
