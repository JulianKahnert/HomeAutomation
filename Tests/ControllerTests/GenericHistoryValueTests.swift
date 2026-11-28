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

    // MARK: Localized description

    private let english = Locale(identifier: "en_US")
    private let german = Locale(identifier: "de_DE")

    @Test func localizedDescriptionInEnglish() {
        let cases: [(EntityHistoryItem, String)] = [
            (EntityHistoryItem(timestamp: date, valueKind: "temperatureSensor", value: .number(21.5)), "21.5°C"),
            (EntityHistoryItem(timestamp: date, valueKind: "relativeHumiditySensor", value: .number(48)), "48.0%"),
            (EntityHistoryItem(timestamp: date, valueKind: "switcher", value: .bool(true)), "On"),
            (EntityHistoryItem(timestamp: date, valueKind: "motionSensor", value: .bool(false)), "No motion"),
            (EntityHistoryItem(timestamp: date, valueKind: "lock", value: .bool(true)), "Locked"),
            (EntityHistoryItem(timestamp: date, valueKind: "targetTemperature", value: .number(20)), "Target 20.0°C"),
            (EntityHistoryItem(timestamp: date, valueKind: "heatingMode", value: .number(Double(HeatingMode.auto.rawValue))), "Mode Auto"),
            (EntityHistoryItem(timestamp: date, valueKind: "color", value: .text("1.0 0.0 0.0")), "0° hue")
        ]
        for (item, expected) in cases {
            #expect(item.localizedValueDescription(locale: english) == expected)
        }
    }

    @Test func localizedDescriptionFollowsTheLocaleForNumbers() {
        let item = EntityHistoryItem(timestamp: date, valueKind: "temperatureSensor", value: .number(21.5))
        #expect(item.localizedValueDescription(locale: english) == "21.5°C")
        #expect(item.localizedValueDescription(locale: german) == "21,5°C")
    }

    @Test func localizedDescriptionNamesTheHeatingModeForPeople() {
        let item = EntityHistoryItem(timestamp: date, valueKind: "heatingMode", value: .number(Double(HeatingMode.heat.rawValue)))
        #expect(item.localizedValueDescription(locale: english) == "Mode Heat")
        #expect(HeatingMode.heat.name == "heat")
    }

    @Test func localizedDescriptionOfADeadline() {
        func item(_ deadline: Deadline) -> EntityHistoryItem {
            EntityHistoryItem(timestamp: date, valueKind: "deadline", value: .text(deadline.text))
        }
        #expect(item(.none).localizedValueDescription(locale: english) == "No deadline")
        #expect(item(.running(until: date)).localizedValueDescription(locale: english) == "Until \(date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: english)))")
        #expect(item(.overdue(since: date)).localizedValueDescription(locale: english).hasPrefix("Overdue since "))
    }

    @Test func localizedDescriptionKeepsTheRawValueForUnknownKinds() {
        let number = EntityHistoryItem(timestamp: date, valueKind: "futureKind", value: .number(3.5))
        #expect(number.localizedValueDescription(locale: german) == "futureKind: 3.5")
        let text = EntityHistoryItem(timestamp: date, valueKind: "futureKind", value: .text("abc"))
        #expect(text.localizedValueDescription(locale: english) == "futureKind: abc")
    }

    @Test func localizedDescriptionWithoutAValueSaysNoData() {
        let item = EntityHistoryItem(timestamp: date, valueKind: nil, value: nil)
        #expect(item.localizedValueDescription(locale: english) == "No data")
    }
}
