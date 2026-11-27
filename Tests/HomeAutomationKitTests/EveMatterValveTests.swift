//
//  EveMatterValveTests.swift
//  HomeAutomationKit
//

@testable import Adapter
import HAModels
import Testing

struct EveMatterValveTests {
    private let bathroom = EntityId(placeId: "Bad OG", name: "Eve Thermo Bad OG", characteristicsName: "Heizung", characteristic: .valvePosition)
    private let livingRoom = EntityId(placeId: "Kaminzimmer", name: "Eve Thermo Kaminzimmer", characteristicsName: "Heizung", characteristic: .valvePosition)

    @Test("Raw values within 0...100 are the valve position in percent", arguments: [
        (UInt64(0), 0), (42, 42), (71, 71), (100, 100)
    ])
    func mapsPercent(rawValue: UInt64, expected: Int) {
        #expect(EveMatterValve.percent(fromRawValue: rawValue) == expected)
    }

    @Test("Raw values above 100 are skipped", arguments: [UInt64(101), 255, UInt64.max])
    func skipsOutOfRange(rawValue: UInt64) {
        #expect(EveMatterValve.percent(fromRawValue: rawValue) == nil)
    }

    @Test("Raw calibration values are tenths of a degree Celsius", arguments: [
        (Int64(0), 0.0), (-5, -0.5), (25, 2.5), (-25, -2.5), (127, 12.7), (-127, -12.7)
    ])
    func mapsCalibration(rawValue: Int64, expected: Double) {
        #expect(EveMatterValve.calibrationInC(fromRawValue: rawValue) == expected)
    }

    @Test("Raw calibration values outside int8, and the int8 null value -128, are skipped", arguments: [Int64(-128), 128, -129, Int64.max])
    func skipsCalibrationOutOfRange(rawValue: Int64) {
        #expect(EveMatterValve.calibrationInC(fromRawValue: rawValue) == nil)
    }

    @Test("Only an endpoint with the Thermostat cluster is a thermostat")
    func detectsThermostat() {
        // Eve Thermo: Descriptor, Identify, Thermostat, Eve vendor cluster
        #expect(EveMatterValve.isThermostat(serverClusterIDs: [0x001D, 0x0003, 0x0201, 0x130A_FC01]))
        // Eve Thermo Control: Eve clusters, but no Thermostat
        #expect(!EveMatterValve.isThermostat(serverClusterIDs: [0x001D, 0x0003, 0x0402, 0x130A_FC01]))
        #expect(!EveMatterValve.isThermostat(serverClusterIDs: []))
    }

}
