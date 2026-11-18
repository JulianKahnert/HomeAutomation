//
//  EveCharacteristic.swift
//  Adapter
//

/// Eve-specific HomeKit characteristics that HomeKit reports as "Custom" because they have no standard type.
enum EveCharacteristic {
    /// Valve position in percent (UInt8, 0...100, read + notify), e.g. on the Eve Thermo.
    static let valvePositionUUID = "E863F12E-079E-48FF-8F27-9C2605A29F52"

    /// Whether a HomeKit characteristic type string is the Eve valve position (case-insensitive).
    static func isValvePosition(_ characteristicType: String) -> Bool {
        characteristicType.uppercased() == valvePositionUUID
    }
}
