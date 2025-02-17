//
//  Other.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 20.07.24.
//

import Foundation
@testable import HAModels
import Testing

struct OtherTests {

    @Test("Test date equality", arguments: [
        (dateString1: "2024-07-20T21:24:06Z", dateString2: "2024-07-20T21:24:06Z", result: true),
        (dateString1: "2024-07-20T21:24:06Z", dateString2: "2024-07-20T21:24:56Z", result: true),
        (dateString1: "2024-07-20T21:21:06Z", dateString2: "2024-07-20T21:24:56Z", result: false),
        (dateString1: "2024-07-20T21:21:06Z", dateString2: "2024-07-20T21:22:02Z", result: false)
    ])
    func normalizeElevation(arguments: (dateString1: String, dateString2: String, result: Bool)) throws {
        let date1 = try Date(arguments.dateString1, strategy: .iso8601)
        let date2 = try Date(arguments.dateString2, strategy: .iso8601)
        let result = Calendar.current.isDate(date1, equalTo: date2, toGranularity: .minute)

        #expect(result == arguments.result)
    }
}
