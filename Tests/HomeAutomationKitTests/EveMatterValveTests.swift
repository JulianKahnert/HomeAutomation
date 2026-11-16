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
        var detector = ValvePositionChangeDetector()
        let results = [71, 71, 45, 45].map { detector.recordIfChanged($0, for: bathroom) }
        #expect(results == [true, false, true, false])
    }

    @Test("Entities are tracked separately")
    func tracksEntitiesSeparately() {
        var detector = ValvePositionChangeDetector()
        let results = [livingRoom, bathroom, livingRoom].map { detector.recordIfChanged(0, for: $0) }
        #expect(results == [true, true, false])
    }

    @Test("After a reset every entity's next reading is a change again")
    func resetSendsAgain() {
        var detector = ValvePositionChangeDetector()
        let first = detector.recordIfChanged(71, for: bathroom)
        detector.reset()
        let afterReset = detector.recordIfChanged(71, for: bathroom)
        #expect(first)
        #expect(afterReset)
    }
}
