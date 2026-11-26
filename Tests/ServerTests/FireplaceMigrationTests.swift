//
//  FireplaceMigrationTests.swift
//  HomeAutomationServer
//

import Foundation
import HAModels
@testable import Server
import XCTest

final class FireplaceMigrationTests: XCTestCase {
    private func at(_ minutes: Double) -> Date { Date(timeIntervalSince1970: 1_800_000_000 + minutes * 60) }

    func testOnlyChangesOfTheFormerSwitchBecomeSwitches() {
        // an adapter resync repeats a value, an "off" before the first "on" says nothing
        let states = [(at(0), false), (at(10), true), (at(11), true), (at(40), false), (at(41), false), (at(90), true)]

        let switches = CreateFireplaceSwitch.switches(from: states.map { (timestamp: $0.0, isOn: $0.1) })

        XCTAssertEqual(switches, [FireplaceSwitch(timestamp: at(10), isOn: true),
                                  FireplaceSwitch(timestamp: at(40), isOn: false),
                                  FireplaceSwitch(timestamp: at(90), isOn: true)])
    }

    func testUnsortedHistoryIsSortedFirst() {
        let switches = CreateFireplaceSwitch.switches(from: [(timestamp: at(40), isOn: false), (timestamp: at(10), isOn: true)])

        XCTAssertEqual(switches.map(\.isOn), [true, false])
    }
}
