//
//  GenericHistoryValueTests.swift
//  ControllerTests
//

import Foundation
import HAModels
import Testing

@testable import Controller

struct GenericHistoryValueTests {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func numberChartsAsItIs() {
        let item = EntityHistoryItem(timestamp: date, valueKind: "temperatureSensor", value: .number(21.5))
        #expect(item.primaryValue == 21.5)
        #expect(item.stateValue == nil)
    }

    @Test func boolChartsAsStateAndOneOrZero() {
        let item = EntityHistoryItem(timestamp: date, valueKind: "switcher", value: .bool(true))
        #expect(item.stateValue == true)
        #expect(item.primaryValue == 1)
    }

    @Test func colourChartsAsHue() {
        let item = EntityHistoryItem(timestamp: date, valueKind: "color", value: .text("1.0 0.0 0.0"))
        #expect(item.primaryValue == 0)
        #expect(item.color != nil)
    }

    @Test func typedFieldsStillGiveTheGenericValue() {
        let item = EntityHistoryItem(timestamp: date, valueKind: "temperatureSensor", value: .number(19))
        #expect(item.valueKind == "temperatureSensor")
        #expect(item.value == .number(19))
        #expect(item.primaryValue == 19)
    }

    @Test func unknownKindShowsItsRawValueInsteadOfFailing() {
        let number = EntityHistoryItem(timestamp: date, valueKind: "futureKind", value: .number(3.5))
        #expect(number.descriptor == nil)
        #expect(number.valueDescription == "futureKind: 3.5")
        #expect(number.primaryValue == 3.5)

        let text = EntityHistoryItem(timestamp: date, valueKind: "futureKind", value: .text("abc"))
        #expect(text.valueDescription == "futureKind: abc")
        #expect(text.primaryValue == nil)
    }
}
