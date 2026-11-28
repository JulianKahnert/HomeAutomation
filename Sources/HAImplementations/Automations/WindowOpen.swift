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
        case .time, .sunrise, .sunset, .configDeployed:
            return false
        }
    }

    public func execute(using hm: HomeManagable) async throws {
        try await execute(using: hm, on: AutomationRunContext.event, now: Date(), sleep: { try await Task.sleep(for: $0) })
    }

    /// Reports the open window's deadline and its überschritten state at the Fensterschließzeit.
    ///
    /// - On a report (`event`) the window opened `now`. On a server start it has been open since the timestamp
    ///   of its contact's current state, so the Live Activity keeps its real opening time and the run waits
    ///   only for the rest of the Lüftungslimit.
    func execute(using hm: HomeManagable, on event: HomeEvent?, now: Date, sleep: @Sendable (Duration) async throws -> Void) async throws {
        log.debug("Executing 'WindowOpen' automation")
        let contact = try await hm.getCurrentEntity(with: windowContact.contactSensorId)
        let isWindowOpen = try contact.isContactOpen.get(with: log)

        // Clear window state when window closes early
        guard isWindowOpen else {
            log.debug("Skipping 'WindowOpen' automation, window is closed")
            try await reportDeadline(.none, using: hm)
            return
        }

        // A window whose deadline is already stored keeps it: a replay of "open" (the adapter's resync after
        // a server start) must not restart its Lüftungslimit.
        let closeBy: Date
        if let stored = await storedDeadline(using: hm)?.end {
            closeBy = stored
        } else {
            let opened = event == .serverStarted ? contact.timestamp : now
            closeBy = opened.addingTimeInterval(notificationWait.timeInterval)
        }

        try await reportDeadline(.running(until: closeBy), using: hm)

        let remaining = closeBy.timeIntervalSince(now)
        if remaining > 0 {
            log.debug("Start sleeping until the Fensterschließzeit", metadata: ["remaining": "\(remaining)"])
            try await sleep(.seconds(remaining))
        }

        // The window projection shows the window überschritten and alerts the resident.
        log.debug("Fensterschließzeit reached, reporting the window überschritten")
        try await reportDeadline(.overdue(since: closeBy), using: hm)
    }

    /// The server-owned entity that holds this window's deadline, one per window.
    public var deadlineId: EntityId {
        let id = windowContact.contactSensorId
        return .serverOwned(name: "\(id.placeId)/\(id.name)", characteristic: .deadline)
    }

    /// Reports the deadline of this window unless it already holds it. An overdue deadline is never taken back
    /// to running for the same end, so a replay after a restart changes nothing and sends nothing.
    private func reportDeadline(_ deadline: Deadline, using homeManager: HomeManagable) async throws {
        // The stored deadline went through its text form, which can move the end by a fraction of a microsecond;
        // compare in that form so the same end counts as the same deadline.
        let deadline = Deadline(text: deadline.text) ?? deadline
        // Decided where the state is set, so a report of another writer in between cannot be overwritten blindly.
        // (`report` itself leaves a value-identical replay alone.)
        try await homeManager.report(deadlineId, value: .text(deadline.text), origin: .server, ifCurrent: { item in
            if case .running(let until) = deadline { return item?.deadline != .overdue(since: until) }
            return true
        })
    }

    /// The deadline this window holds, `nil` when none is stored or it is `none`.
    private func storedDeadline(using hm: HomeManagable) async -> Deadline? {
        let deadline = try? await hm.getCurrentEntity(with: deadlineId).deadline
        return deadline?.end == nil ? nil : deadline
    }
}
