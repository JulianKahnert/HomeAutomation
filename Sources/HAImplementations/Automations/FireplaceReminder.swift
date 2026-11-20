//
//  FireplaceReminder.swift
//  HAImplementations
//

import Foundation
import HAModels

/// Asks "Kamin an?" by push when the temperature in the fireplace room rises quickly (glossary: fireplace reminder).
///
/// It never switches the fireplace: the push carries the fireplace category, whose action switches it on.
public struct FireplaceReminder: Automatable {
    public var isActive = true
    public let name: String
    public let roomSensor: EntityId
    public let fireplace: SwitchDevice
    /// The rise in °C within `window` that triggers the reminder.
    public let riseInC: Double
    /// The time span the rise is measured over.
    public let window: TimeInterval
    /// No second reminder before this much time has passed since the last one.
    public let minInterval: TimeInterval

    public var triggerEntityIds: Set<EntityId> { [roomSensor] }

    public init(_ name: String = "fireplace-reminder", roomSensor: EntityId, fireplace: SwitchDevice = Fireplace.switchDevice, riseInC: Double = 1.0, window: TimeInterval = 30 * 60, minInterval: TimeInterval = 2 * 3600) {
        self.name = name
        self.roomSensor = roomSensor
        self.fireplace = fireplace
        self.riseInC = riseInC
        self.window = window
        self.minInterval = minInterval
    }

    public func shouldTrigger(with event: HomeEvent, using hm: HomeManagable) async throws -> Bool {
        guard case .change(let item) = event, item.entityId == roomSensor,
              let current = item.temperatureInC?.value else { return false }
        guard !(await Fireplace.state(of: fireplace.switchId, with: hm).isOn) else { return false }
        if let last = await hm.lastNotificationDate(id: Fireplace.reminderNotificationId),
           item.timestamp.timeIntervalSince(last) < minInterval { return false }

        let history = await hm.getEntityHistory(with: roomSensor, since: item.timestamp.addingTimeInterval(-window))
        guard let lowest = history.compactMap({ $0.temperatureInC?.value }).min() else { return false }
        return current - lowest >= riseInC
    }

    public func execute(using hm: HomeManagable) async throws {
        await hm.sendNotification(title: "Kamin an?",
                                  message: "Heizkörper ausschalten",
                                  id: Fireplace.reminderNotificationId,
                                  category: Fireplace.notificationCategory)
    }
}
