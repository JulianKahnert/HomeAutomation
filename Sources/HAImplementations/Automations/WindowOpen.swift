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
        switch event {
        case .change(let item):
            return windowContact.contactSensorId == item.entityId
        case .serverStarted:
            // Set the window up again from the current state, without waiting for the adapter to re-send it.
            do {
                return try await windowContact.isContactOpen(with: hm)
            } catch {
                log.warning("Contact unreadable on server start, window not set up again",
                            metadata: ["entityId": "\(windowContact.contactSensorId)", "error": "\(error)"])
                return false
            }
        default:
            return false
        }
    }

    public func execute(using hm: HomeManagable) async throws {
        let isServerStart = AutomationRunContext.event == .serverStarted
        try await execute(using: hm, now: Date(), isServerStart: isServerStart, sleep: { try await Task.sleep(for: $0) })
    }

    /// Registers the open window and marks it überschritten at its Fensterschließzeit.
    ///
    /// - On a report the window opened `now`. On a server start it has been open since the timestamp of its
    ///   contact's current state, so the Live Activity keeps its real opening time and the run waits only
    ///   for the rest of the Lüftungslimit.
    func execute(using hm: HomeManagable, now: Date, isServerStart: Bool, sleep: @Sendable (Duration) async throws -> Void) async throws {
        log.debug("Executing 'WindowOpen' automation")
        let contact = try await hm.getCurrentEntity(with: windowContact.contactSensorId)
        let isWindowOpen = try contact.isContactOpen.get(with: log)

        // Clear window state when window closes early
        guard isWindowOpen else {
            log.debug("Skipping 'WindowOpen' automation, window is closed")
            await hm.setWindowOpenState(entityId: windowContact.contactSensorId, to: nil)
            return
        }

        // A window already registered keeps its opening time: a replay of "open" (the adapter's resync after
        // a server start) must not restart its Lüftungslimit.
        let closeBy: Date
        if let registered = await registeredWindow(using: hm) {
            closeBy = registered.closeBy
        } else {
            let opened = isServerStart ? contact.timestamp : now
            let state = WindowOpenState(entityId: windowContact.contactSensorId, opened: opened, maxOpenDuration: notificationWait.timeInterval)
            await hm.setWindowOpenState(entityId: windowContact.contactSensorId, to: state)
            closeBy = state.closeBy
        }

        let remaining = closeBy.timeIntervalSince(now)
        if remaining > 0 {
            log.debug("Start sleeping until the Fensterschließzeit", metadata: ["remaining": "\(remaining)"])
            try await sleep(.seconds(remaining))
        }

        // The Live Activity marks the window überschritten and alerts the resident.
        log.debug("Fensterschließzeit reached, marking window überschritten")
        await hm.markWindowOverdue(entityId: windowContact.contactSensorId)
    }

    /// This offene Fenster as the Live Activity shows it, `nil` when it is not registered.
    private func registeredWindow(using hm: HomeManagable) async -> WindowContentState.Window? {
        let id = WindowContentState.Window.id(room: windowContact.contactSensorId.placeId, name: windowContact.contactSensorId.name)
        return await hm.getWindowContentState().windows.first { $0.id == id }
    }
}
