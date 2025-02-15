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
}
