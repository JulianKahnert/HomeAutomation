//
//  RoomContact.swift
//  HAModels
//

import Foundation

/// A contact that switches the radiators of a room off while it is open (glossary: contact): a window
/// contact today, the fireplace switch later. One rule for all of them; only how "open" is read differs.
public enum RoomContact: Codable, Sendable {
    case window(ContactSensorDevice)

    public var entityId: EntityId {
        switch self {
        case .window(let sensor):
            return sensor.contactSensorId
        }
    }

    /// Whether `item`, a state of this contact's entity, says open. An item without the value counts as closed.
    public func isOpen(_ item: EntityStorageItem) -> Bool {
        switch self {
        case .window:
            return item.isContactOpen ?? false
        }
    }

    /// The current state of the contact, or `nil` when it is unreachable or unknown. The caller treats
    /// `nil` as closed ("unreachable = closed").
    public func currentState(with hm: HomeManagable) async -> (isOpen: Bool, since: Date)? {
        guard let item = try? await hm.getCurrentEntity(with: entityId) else { return nil }
        return (isOpen(item), item.timestamp)
    }

    /// The state before the current one, `nil` when there is none.
    public func previousState(with hm: HomeManagable) async -> (isOpen: Bool, since: Date)? {
        guard let item = try? await hm.getPreviousEntity(with: entityId) else { return nil }
        return (isOpen(item), item.timestamp)
    }
}
