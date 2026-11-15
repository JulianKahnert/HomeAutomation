//
//  EveMatterValve.swift
//  HAModels
//

/// Where an Eve Thermo paired over Matter reports its valve position, and how the adapter turns it into a `valvePosition` value.
///
/// Over Matter, HomeKit shows the Eve Thermo as a HeaterCooler without the Eve valve characteristic
/// (`EveCharacteristic.valvePositionUUID`), and the Thermostat cluster has no `PIHeatingDemand`. The
/// value lives in an Eve vendor attribute instead, read through the home's Matter controller.
public enum EveMatterValve {
    /// The endpoint that carries the Thermostat cluster and the Eve vendor cluster.
    public static let endpointID: UInt16 = 1
    /// Eve vendor cluster on the Eve Thermo.
    public static let clusterID: UInt32 = 0x130A_FC01
    /// Valve opening in percent (unsigned integer), compared live with the Eve app.
    public static let valvePositionAttributeID: UInt32 = 0x130A_0018
    /// Matter Thermostat cluster. Only accessories whose endpoint 1 has it are thermostats; the Eve Thermo
    /// Control (a room sensor) also carries Eve clusters but not this one.
    public static let thermostatClusterID: UInt32 = 0x0201
    /// Matter Descriptor cluster and its `ServerList` attribute, the cluster IDs an endpoint serves.
    public static let descriptorClusterID: UInt32 = 0x001D
    public static let serverListAttributeID: UInt32 = 0x0001

    /// Whether an endpoint serving these clusters is a thermostat whose valve position can be read.
    public static func isThermostat(serverClusterIDs: [UInt32]) -> Bool {
        serverClusterIDs.contains(thermostatClusterID)
    }

    /// The valve position for a raw attribute value, `nil` when it is outside 0...100 percent.
    public static func percent(fromRawValue rawValue: UInt64) -> Int? {
        guard rawValue <= 100 else { return nil }
        return Int(rawValue)
    }
}

/// Remembers the last valve position sent per entity, so the adapter sends a value only when it changed.
public struct ValvePositionChangeDetector: Sendable {
    private var lastSent: [EntityId: Int] = [:]

    public init() {}

    /// Whether `percent` differs from the last value recorded for `entityId`; records it when it does.
    public mutating func recordIfChanged(_ percent: Int, for entityId: EntityId) -> Bool {
        guard lastSent[entityId] != percent else { return false }
        lastSent[entityId] = percent
        return true
    }

    /// Forgets every recorded value, so the next reading of each entity counts as a change.
    public mutating func reset() {
        lastSent.removeAll()
    }
}
