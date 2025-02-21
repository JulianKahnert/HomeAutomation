//
//  Automatable.swift
//  
//
//  Created by Julian Kahnert on 02.07.24.
//

import Logging

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

    func getEntityIds() -> [EntityId] {
        findAllEntityIds(in: self, maxDepth: 20)
    }

    private func findAllEntityIds(in object: Any, maxDepth: Int) -> [EntityId] {
        // If the maximum depth is reached, stop recursion
        guard maxDepth > 0 else {
            return []
        }

        var entityIds: [EntityId] = []
        let mirror = Mirror(reflecting: object)

        for child in mirror.children {
            let reflectedChild = Mirror(reflecting: child.value)

            switch reflectedChild.displayStyle {

            case .class, .struct:
                // Recursively search for UUIDs in classes and structs
                entityIds.append(contentsOf: findAllEntityIds(in: child.value, maxDepth: maxDepth - 1))

            case .collection:
                // Recursively search for UUIDs in collections (e.g., Arrays, Sets)
                for element in reflectedChild.children {
                    entityIds.append(contentsOf: findAllEntityIds(in: element.value, maxDepth: maxDepth - 1))
                }

            case .dictionary:
                // Recursively search for UUIDs in both keys and values in dictionaries
                for element in reflectedChild.children {
                    guard let (key, value) = element.value as? (Any, Any) else {
                        assertionFailure()
                        continue
                    }
                    entityIds.append(contentsOf: findAllEntityIds(in: key, maxDepth: maxDepth - 1))
                    entityIds.append(contentsOf: findAllEntityIds(in: value, maxDepth: maxDepth - 1))
                }

            case .optional:
                // Unwrap optional and recursively search if there's a value
                if let unwrappedValue = reflectedChild.children.first?.value {
                    entityIds.append(contentsOf: findAllEntityIds(in: unwrappedValue, maxDepth: maxDepth - 1))
                }

            default:
                // Handle other types (e.g., enums, tuples, etc.) - do nothing by default
                break
            }

            // Check if the current value is a EntityId
            if let entityId = child.value as? EntityId {
                entityIds.append(entityId)
            }
        }

        return entityIds
    }
}
