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

    @Test("Valve position and calibration of the same Thermo are tracked separately")
    func tracksCharacteristicsSeparately() {
        let calibration = EntityId(placeId: "Bad OG", name: "Eve Thermo Bad OG", characteristicsName: "Heizung", characteristic: .temperatureCalibration)
        var detector = MatterReadingChangeDetector()
        let results = [(bathroom, 5), (calibration, 5), (bathroom, 5), (calibration, -5)].map { detector.recordIfChanged($1, for: $0) }
        #expect(results == [true, true, false, true])
    }

    @Test("Only an endpoint with the Thermostat cluster is a thermostat")
    func detectsThermostat() {
        // Eve Thermo: Descriptor, Identify, Thermostat, Eve vendor cluster
        #expect(EveMatterValve.isThermostat(serverClusterIDs: [0x001D, 0x0003, 0x0201, 0x130A_FC01]))
        // Eve Thermo Control: Eve clusters, but no Thermostat
        #expect(!EveMatterValve.isThermostat(serverClusterIDs: [0x001D, 0x0003, 0x0402, 0x130A_FC01]))
        #expect(!EveMatterValve.isThermostat(serverClusterIDs: []))
    }

    @Test("The first reading of an entity is a change, the same value again is not")
    func detectsFirstReadingAndRepeats() {
        var detector = MatterReadingChangeDetector()
        let results = [71, 71, 45, 45].map { detector.recordIfChanged($0, for: bathroom) }
        #expect(results == [true, false, true, false])
    }

    @Test("Entities are tracked separately")
    func tracksEntitiesSeparately() {
        var detector = MatterReadingChangeDetector()
        let results = [livingRoom, bathroom, livingRoom].map { detector.recordIfChanged(0, for: $0) }
        #expect(results == [true, true, false])
    }

    @Test("After a reset every entity's next reading is a change again")
    func resetSendsAgain() {
        var detector = MatterReadingChangeDetector()
        let first = detector.recordIfChanged(71, for: bathroom)
        detector.reset()
        let afterReset = detector.recordIfChanged(71, for: bathroom)
        #expect(first)
        #expect(afterReset)
    }
}
