//
//  EveMatterValve.swift
//  Adapter
//

import HAModels

/// Where an Eve Thermo paired over Matter reports its valve position and temperature offset, and how the
/// adapter turns them into `valvePosition` and `temperatureCalibration` values.
///
/// Over Matter, HomeKit shows the Eve Thermo as a HeaterCooler without the Eve valve characteristic
/// (`EveCharacteristic.valvePositionUUID`), and the Thermostat cluster has no `PIHeatingDemand`. The
/// value lives in an Eve vendor attribute instead, read through the home's Matter controller.
enum EveMatterValve {
    /// The endpoint that carries the Thermostat cluster and the Eve vendor cluster.
    static let endpointID: UInt16 = 1
    /// Eve vendor cluster on the Eve Thermo.
    static let clusterID: UInt32 = 0x130A_FC01
    /// Valve opening in percent (unsigned integer), compared live with the Eve app.
    static let valvePositionAttributeID: UInt32 = 0x130A_0018
    /// Matter Thermostat cluster. Only accessories whose endpoint 1 has it are thermostats; the Eve Thermo
    /// Control (a room sensor) also carries Eve clusters but not this one.
    static let thermostatClusterID: UInt32 = 0x0201
    /// Thermostat `LocalTemperatureCalibration` (int8, 0.1 °C), the Eve app's "Temperaturabweichung".
    /// The Thermostat's `LocalTemperature` already includes it.
    static let localTemperatureCalibrationAttributeID: UInt32 = 0x0010
    /// Global `ClusterRevision` attribute; on the Thermostat cluster it tells which calibration range applies.
    static let clusterRevisionAttributeID: UInt32 = 0xFFFD
    /// Matter Descriptor cluster and its `ServerList` attribute, the cluster IDs an endpoint serves.
    static let descriptorClusterID: UInt32 = 0x001D
    static let serverListAttributeID: UInt32 = 0x0001

    /// Whether an endpoint serving these clusters is a thermostat whose valve position can be read.
    static func isThermostat(serverClusterIDs: [UInt32]) -> Bool {
        serverClusterIDs.contains(thermostatClusterID)
    }

    /// The valve position for a raw attribute value, `nil` when it is outside 0...100 percent.
    static func percent(fromRawValue rawValue: UInt64) -> Int? {
        guard rawValue <= 100 else { return nil }
        return Int(rawValue)
    }

    /// The temperature offset in Celsius for a raw `LocalTemperatureCalibration`, `nil` outside int8 or for
    /// -128, which int8 attributes use as "no value".
    static func calibrationInC(fromRawValue rawValue: Int64) -> Double? {
        guard (-127...127).contains(rawValue) else { return nil }
        return Double(rawValue) / 10
    }
}
