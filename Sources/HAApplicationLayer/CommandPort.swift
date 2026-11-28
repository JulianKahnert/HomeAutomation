//
//  CommandPort.swift
//  HAApplicationLayer
//

import HAModels

/// What a write sets: the state after the write and whether it changed.
public struct StateChange: Sendable, Equatable {
    public let item: EntityStorageItem
    public let changed: Bool

    public init(item: EntityStorageItem, changed: Bool) {
        self.item = item
        self.changed = changed
    }
}

/// Why a command did not run to its end.
public enum CoreCommandError: Error, Equatable {
    /// The value does not fit the shape of the entity's value kind.
    case valueDoesNotFit(EntityId)
    /// The entity is not one the server can set (not server-owned).
    case notSettable(EntityId)
    /// The state that was just set cannot be read back.
    case stateUnreadable(EntityId)
    /// A deploy that names entities HomeKit does not know.
    case unknownEntities(Set<EntityId>)
    /// The core did not answer in time; the command is handled when the event loop reaches it.
    case timedOut(command: String)
}

/// The one way the API layer writes into the server core. The API layer reads through repositories and knows
/// no `HomeManager` or `AutomationService`; an implementation hands each command to the core.
public protocol CommandPort: Sendable {
    /// Sets the state of a server-owned entity with origin `app` and answers the new state.
    func setState(_ entityId: EntityId, value: Value) async throws -> StateChange
    /// Activates (`true`) or deactivates (`false`) an automation by name.
    func setAutomationActive(name: String, to isActive: Bool) async throws
    /// Cancels the run of an automation by name; nothing happens when it is not running.
    func stopAutomation(name: String) async throws
    /// Replaces the deployed automations and stores them with the location.
    /// - Parameter skipValidation: Deploy although entities are unknown to HomeKit.
    func deploy(_ automations: [any Automatable], location: Location, skipValidation: Bool) async throws
}
