//
//  WindowOpen.swift
//
//
//  Created by Julian Kahnert on 01.07.24.
//

import Foundation
import HAModels
import Shared

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

        // Clear window state when window closes early
        guard isWindowOpen else {
            log.debug("Skipping 'WindowOpen' automation, window is closed")
            await hm.setWindowOpenState(entityId: windowContact.contactSensorId, to: nil)
            return
        }

        // Set window state for tracking
        let opened = Date()
        let state = WindowOpenState(entityId: windowContact.contactSensorId, opened: opened, maxOpenDuration: notificationWait.timeInterval)
        await hm.setWindowOpenState(entityId: windowContact.contactSensorId, to: state)

        let end = opened.addingTimeInterval(notificationWait.timeInterval)

        log.debug("Start sleeping for \(notificationWait.description) before sending notification")
        var shouldWait = true
        while shouldWait {
            let waitSeconds = min(60, end.timeIntervalSinceNow)
            try await Task.sleep(for: .seconds(waitSeconds))

            if end.timeIntervalSinceNow <= 5 {
                shouldWait = false
            }
        }

        log.debug("Start sending notification")
        let message = "\(windowContact.contactSensorId.name) (\(windowContact.contactSensorId.placeId))"

        await TibberService()?.sendNotification(title: "🪟 offen", message: message)
        await hm.sendNotification(title: "🪟 offen", message: message)
        log.debug("End sending notification")
    }
}
