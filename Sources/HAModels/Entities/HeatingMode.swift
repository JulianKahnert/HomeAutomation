//
//  HeatingMode.swift
//  HomeAutomationKit
//

/// Thermostat target mode, HAP `TargetHeatingCoolingState`. The raw value is the HomeKit value and
/// is what the database stores (`entityChanges.number`).
///
/// A raw value outside 0...3 (a future HAP mode) has no case: the adapter and the database mapping
/// turn it into `nil` and log it instead of crashing.
public enum HeatingMode: Int, Codable, Sendable, CaseIterable {
    case off = 0
    case heat = 1
    case cool = 2
    case auto = 3

    /// Name used on the HTTP API (`off`, `heat`, `cool`, `auto`).
    public var name: String {
        switch self {
        case .off: "off"
        case .heat: "heat"
        case .cool: "cool"
        case .auto: "auto"
        }
    }

    public init?(name: String) {
        guard let mode = Self.allCases.first(where: { $0.name == name }) else { return nil }
        self = mode
    }
}
