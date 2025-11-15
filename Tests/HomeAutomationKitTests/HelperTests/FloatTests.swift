//
//  FloatTests.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 20.07.24.
//

import Foundation
@testable import HAModels
import Testing

struct FloatTests {

    @Test("Test time is equal", arguments: [
        (value: 0.5, range: 0.5...1, result: 0.75),
        (value: 0.2, range: 0.5...1, result: 0.6),
        (value: 0.1, range: 0.3...1, result: 0.37),
        (value: 0.1, range: 1...1, result: 1)
    ])
    func scaling(arguments: (value: Float, range: ClosedRange<Float>, result: Float)) throws {
        let result = arguments.value.scale(to: arguments.range)
        #expect(result == arguments.result)
    }

    @Test("Test float rounding to 2 decimal places", arguments: [
        (value: 1.234567, places: 2, expected: 1.23),
        (value: 1.235, places: 2, expected: 1.24),
        (value: 0.999, places: 2, expected: 1.0),
        (value: 0.994, places: 2, expected: 0.99),
        (value: 0.001, places: 2, expected: 0.0),
        (value: 0.005, places: 2, expected: 0.01),
        (value: 100.123456, places: 2, expected: 100.12),
        (value: -1.234567, places: 2, expected: -1.23),
        (value: -1.235, places: 2, expected: -1.24)
    ])
    func rounding(arguments: (value: Float, places: Int, expected: Float)) throws {
        let result = arguments.value.rounded(toPlaces: arguments.places)
        #expect(result == arguments.expected)
    }

    @Test("Test float rounding to different decimal places", arguments: [
        (value: 1.23456, places: 0, expected: 1.0),
        (value: 1.23456, places: 1, expected: 1.2),
        (value: 1.23456, places: 3, expected: 1.235),
        (value: 1.23456, places: 4, expected: 1.2346)
    ])
    func roundingDifferentPlaces(arguments: (value: Float, places: Int, expected: Float)) throws {
        let result = arguments.value.rounded(toPlaces: arguments.places)
        #expect(result == arguments.expected)
    }
}
