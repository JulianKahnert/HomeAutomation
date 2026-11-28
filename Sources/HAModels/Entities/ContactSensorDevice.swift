//
//  ContactSensorDevice.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 13.02.25.
//

import Foundation
import Shared

open class ContactSensorDevice: Codable, @unchecked Sendable, Log {
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

}
