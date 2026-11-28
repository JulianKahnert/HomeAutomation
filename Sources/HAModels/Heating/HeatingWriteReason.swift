//
//  HeatingWriteReason.swift
//  HAModels
//

import Foundation

/// Why the server wrote a radiator. A fixed list on purpose: "observed" is not a reason, it is derived
/// when the Heizung tab is prepared (see the glossary).
public enum HeatingWriteReason: String, Sendable, Codable, CaseIterable {
    /// A switch point of the room's plan.
    case plan
    /// A window contact of the room opened or closed.
    case window
    /// A fireplace the room follows was switched on or off.
    case fireplace
    /// Everything else, e.g. a configuration deploy or a timeout.
    case system
}

/// Carries the reason of a radiator write down to `HomeManager.perform(_:)` without changing the
/// signature of `HomeManagable`, like `AutomationRunContext` does for the run id.
public enum HeatingWriteContext {
    @TaskLocal public static var current: HeatingWriteReason?

    /// Runs `operation` so that every radiator write inside it is recorded with `reason`.
    public static func withReason<Result>(_ reason: HeatingWriteReason,
                                          operation: () async throws -> Result) async rethrows -> Result {
        try await $current.withValue(reason, operation: operation)
    }
}

/// A radiator command is a journal command row (`ActionLogItem`) with a reason and a value; these accessors
/// read it as the Heizung tab needs it.
public extension ActionLogItem {
    /// Whether this is a command that reached a radiator and carries a reason: the rows the events are built from.
    var isExecutedHeatingWrite: Bool { status == .executed && reason != nil && value != nil }

    /// The room of the radiator.
    var placeId: String { entityId.placeId }

    /// The value written by `setHeating`; `nil` for every other command.
    var isActive: Bool? { actionName == HomeManagableAction.setHeatingName ? value.map { $0 != 0 } : nil }

    /// The °C written by `setTargetTemperature`; `nil` for every other command.
    var targetTemperatureInC: Double? { actionName == HomeManagableAction.setTargetTemperatureName ? value : nil }
}
