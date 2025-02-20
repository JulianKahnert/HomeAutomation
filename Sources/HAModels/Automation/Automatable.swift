//
//  Automatable.swift
//  
//
//  Created by Julian Kahnert on 02.07.24.
//

import Logging

#warning("TODO: validate, that the names of all automations are unique")

/// A protocol that describes an automated process.
/// Any object conforming to this protocol can execute actions based on specific triggers,
/// such as sensors or other entities.
///
/// **Attention:** All new scenes must also be added to `AnyAutomation`.
public protocol Automatable: Sendable, Codable {

    /// Activate/deactive this automation.
    var isActive: Bool { get set }

    /// The unique name of the automation.
    var name: String { get }

    /// A set of entity IDs that act as triggers for the automation process.
    var triggerEntityIds: Set<EntityId> { get }

    /// Determines if the given event should trigger this automation.
    ///
    /// - Parameters:
    ///   - event: The event that is to be evaluated.
    ///   - hm: An instance of HomeManagable providing the current state or context of the home system.
    /// - Returns: A Boolean value indicating whether the event should trigger the automation.
    /// - Throws: An error if something goes wrong during the evaluation.
    func shouldTrigger(with event: HomeEvent, using hm: HomeManagable) async throws -> Bool

    /// Executes the defined automation process.
    ///
    /// - Parameter hm: An instance of HomeManagable providing the current state or context of the home system.
    /// - Throws: An error if something goes wrong during the execution.
    func execute(using hm: HomeManagable) async throws
}

public extension Automatable {
    var log: Logger {
        Logger(label: String(describing: Self.self))
    }
    var identifier: String {
        // we use a description of all properties (e.g. sensor UUIDs) as the identifier of the automation
        return String(describing: self)
    }
}
