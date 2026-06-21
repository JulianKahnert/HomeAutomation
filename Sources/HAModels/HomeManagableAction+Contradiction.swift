//
//  HomeManagableAction+Contradiction.swift
//  HomeAutomation
//
//  Created by Claude Code on 21.06.26.
//

import Foundation

extension HomeManagableAction {
    /// Tolerance for normalized `0...1` float fields (color temperature, RGB saturation).
    /// Chosen above the 2-decimal granularity applied by ``rounded()`` so that a confirming
    /// device read-back — which HomeKit additionally quantizes — is never mistaken for drift.
    static let floatTolerance: Float = 0.02

    /// Tolerance, in degrees, for the circular hue comparison of ``setRGB`` actions.
    static let hueTolerance: Float = 6

    /// Returns `true` when `item` is a freshly observed device state that *contradicts* this
    /// previously-commanded action — i.e. the device drifted away from what the server last
    /// commanded (for example a scene activated outside the server, or a manual change).
    ///
    /// Returns `false` when:
    /// - the relevant state field is `nil` — an update about a different characteristic carries no
    ///   information about this command and must never invalidate it;
    /// - the field *confirms* the command. This is the crucial case: when the server issues a
    ///   command, HomeKit echoes the resulting change back; that echo confirms the command and must
    ///   not invalidate it, otherwise the command would be re-issued in a loop;
    /// - the action has no observable live characteristic (``addEntityToScene``).
    ///
    /// - Parameter item: A freshly observed state for the same entity as this action.
    /// - Returns: `true` if the state contradicts the command and the cache entry should be reset.
    /// - Precondition: `item.entityId == self.entityId` (guaranteed by the caller).
    /// - Note: `self` is expected to be the value as cached, i.e. already passed through ``rounded()``.
    public func isContradicted(by item: EntityStorageItem) -> Bool {
        switch self {
        case .turnOn:
            guard let isOn = item.isDeviceOn else { return false }
            return isOn == false

        case .turnOff:
            guard let isOn = item.isDeviceOn else { return false }
            return isOn == true

        case .lockDoor:
            guard let isLocked = item.isDoorLocked else { return false }
            return isLocked == false

        case .setHeating(_, let active):
            guard let isHeating = item.isHeaterActive else { return false }
            return isHeating != active

        case .setValve(_, let active):
            guard let isOpen = item.valveOpen else { return false }
            return isOpen != active

        case .setBrightness(_, let value):
            // The action value is normalized `0...1`; the stored brightness is an `Int` percentage
            // `0...100`. The adapter truncates when writing to the device, so allow a 1-point band.
            guard let brightness = item.brightness else { return false }
            let commandedPercent = Int((value * 100).rounded())
            return abs(brightness - commandedPercent) > 1

        case .setColorTemperature(_, let value):
            // Both the action value and the stored value are normalized `0...1` (warm...cold).
            guard let colorTemperature = item.colorTemperature else { return false }
            return abs(colorTemperature - value) > Self.floatTolerance

        case .setRGB(_, let rgb):
            // `setRGB` only writes hue + saturation; the stored color reconstructs RGB using the
            // device's *current* brightness, so comparing raw channels would couple to brightness.
            // Compare in hue/saturation space instead, ignoring hue for near-greys (undefined hue).
            guard let color = item.color else { return false }
            let target = hsv(from: rgb)
            let actual = hsv(from: color)

            // When the device reads back as essentially black (off / brightness 0) the reported
            // hue and saturation are meaningless — treat as no information rather than drift.
            guard actual.v > Self.floatTolerance else { return false }

            if abs(target.s - actual.s) > Self.floatTolerance { return true }

            if target.s > Self.floatTolerance, actual.s > Self.floatTolerance {
                let diff = abs(target.h - actual.h)
                return min(diff, 360 - diff) > Self.hueTolerance
            }
            return false

        case .addEntityToScene:
            // Scene authoring, not a live device characteristic: there is nothing to compare
            // against. Such entries are only ever expired via the cache TTL.
            return false
        }
    }
}
