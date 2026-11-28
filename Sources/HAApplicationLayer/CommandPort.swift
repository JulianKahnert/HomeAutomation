//
//  CommandPort.swift
//  HAApplicationLayer
//

import HAModels

/// Why a command did not run to its end.
public enum CoreCommandError: Error, Equatable {
    /// The state that was just set cannot be read back.
    case stateUnreadable(EntityId)
    /// A deploy that names entities HomeKit does not know.
    case unknownEntities(Set<EntityId>)
    /// The core did not answer in time; the command is handled when the event loop reaches it.
    case timedOut(command: String)
    /// The command was dropped before the event loop took it (the stream ended, the server is shutting down); it will not run.
    case dropped
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
