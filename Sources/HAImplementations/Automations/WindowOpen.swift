//
//  WindowOpen.swift
//
//
//  Created by Julian Kahnert on 01.07.24.
//

import Foundation
import HAModels

public struct WindowOpen: Automatable {
    public var isActive = true
    public let name: String
    public let windowContact: ContactSensorDevice
    public let notificationWait: Duration
    public var triggerEntityIds: Set<EntityId> {
        [windowContact.contactSensorId]
    }

    public init(_ name: String, windowContact: ContactSensorDevice, notificationWait: Duration = .minutes(15)) {
        self.name = name
        self.windowContact = windowContact
        self.notificationWait = notificationWait
    }

    public func shouldTrigger(with event: HomeEvent, using hm: HomeManagable) async throws -> Bool {
        guard case let HomeEvent.change(item) = event,
              windowContact.contactSensorId == item.entityId else {
            return false
        }
        return true
    }

    public func execute(using hm: HomeManagable) async throws {
        log.debug("Executing 'WindowOpen' automation")
        let isWindowOpen = try await windowContact.isContactOpen(with: hm)

        // stop this automation and do not notify anyone, if the window is closed
        guard isWindowOpen else {
            log.debug("Skipping 'WindowOpen' automation, window is closed")
            return
        }

        log.debug("Start sleeping for \(notificationWait.description) before sending notification")
        try await Task.sleep(for: notificationWait)

        log.debug("Get name of window for sending notification")
        let name = "\(windowContact.contactSensorId.name) (\(windowContact.contactSensorId.placeId))"

        log.debug("Start sending notification")
#warning("TODO: add again")
//        await TibberService.shared.sendNotification(title: "🪟 offen", message: name)
        log.debug("End sending notification")
    }
}
