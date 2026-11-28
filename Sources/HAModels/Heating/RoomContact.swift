//
//  RoomContact.swift
//  HAModels
//

import Foundation

/// A contact that switches the radiators of a room off while it is open (glossary: contact): a window
/// contact or the fireplace (on = open). One rule for all of them; only how "open" is read differs.
public enum RoomContact: Codable, Sendable {
    case window(ContactSensorDevice)
    /// The fireplace mode the server holds; on counts as open (glossary: fireplace mode). `radiators` are the
    /// radiators of the room it switches off; `nil` for all of them.
    case fireplace(radiators: [RadiatorDevice]? = nil)

    /// The entity of the contact; the fireplace is the server-owned `Fireplace.stateId`.
    public var entityId: EntityId {
        switch self {
        case .window(let sensor):
            return sensor.contactSensorId
        case .fireplace:
            return Fireplace.stateId
        }
    }

    /// The entity whose changes report this contact.
    public var triggerEntityId: EntityId { entityId }

    /// Whether this contact switches `radiator` off while it is open: a window all radiators of the room,
    /// the fireplace the radiators it lists (all when it lists none).
    public func affects(_ radiator: RadiatorDevice) -> Bool {
        switch self {
        case .window:
            return true
        case .fireplace(let radiators):
            guard let radiators else { return true }
            return radiators.contains { $0.heatingId == radiator.heatingId }
        }
    }

    /// The reason of the radiator writes this contact causes.
    public var reason: HeatingWriteReason {
        switch self {
        case .window: return .window
        case .fireplace: return .fireplace
        }
    }

    /// How long the contact has to stay open before the room goes off: the window delay for a window,
    /// none for the fireplace, which the owner switched on on purpose.
    public func delay(in configuration: HeatingConfiguration) -> TimeInterval {
        switch self {
        case .window: return configuration.windowDelay
        case .fireplace: return 0
        }
    }

    /// Whether `item`, a state of this contact's entity, says open. An item without the value counts as closed.
    public func isOpen(_ item: EntityStorageItem) -> Bool {
        source.isOpen(item)
    }

    /// The event source of this contact.
    public var source: HeatingEventSource {
        switch self {
        case .window:
            return .window
        case .fireplace:
            return .fireplace
        }
    }

    /// The current state of the contact, or `nil` when it is unreachable or unknown. The caller treats
    /// `nil` as closed ("unreachable = closed"). The fireplace counts since its last change;
    /// never switched, it is unknown, so off.
    public func currentState(with hm: HomeManagable) async -> (isOpen: Bool, since: Date)? {
        guard let item = try? await hm.getCurrentEntity(with: entityId) else { return nil }
        return (isOpen(item), item.timestamp)
    }
}
