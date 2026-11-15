//
//  EveCharacteristic.swift
//  HAModels
//

/// Eve-specific HomeKit characteristics that HomeKit reports as "Custom" because they have no standard type.
public enum EveCharacteristic {
    /// Valve position in percent (UInt8, 0...100, read + notify), e.g. on the Eve Thermo.
    public static let valvePositionUUID = "E863F12E-079E-48FF-8F27-9C2605A29F52"

    /// Whether a HomeKit characteristic type string is the Eve valve position (case-insensitive).
    public static func isValvePosition(_ characteristicType: String) -> Bool {
        characteristicType.uppercased() == valvePositionUUID
    }
}
