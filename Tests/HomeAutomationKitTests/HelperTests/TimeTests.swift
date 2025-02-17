//
//  TimeTests.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 03.08.24.
//

import Foundation
@testable import HAImplementations
@testable import HAModels
import Testing

struct TimeTests {

    @Test("Test time is equal", arguments: [
        (dateString: "2024-07-19T23:42:06+02:00", result: true),
        (dateString: "2042-07-20T23:42:06+02:00", result: true),
        (dateString: "2024-07-20T21:41:06+02:00", result: false)
    ])
    func timeEquality(arguments: (dateString: String, result: Bool)) throws {
        setenv("TZ", "Europe/Berlin", 1)
        CFTimeZoneResetSystem()

        let date = try Date(arguments.dateString, strategy: .iso8601)
        let event = HomeEvent.time(date: date)

        let time = Time(hour: 23, minute: 42, weekdays: [])
        #expect(time.isEqual(event) == arguments.result, Comment(stringLiteral: arguments.dateString))
    }

    @Test("Test time is equal with weekday", .tags(Tag.localOnly), arguments: [
        (dateString: "2024-07-19T23:42:06+02:00", weekdays: [Time.Weekday.friday], result: true),
        (dateString: "3300-07-20T23:42:06+02:00", weekdays: [Time.Weekday.friday], result: false),
        (dateString: "2024-07-20T23:42:06+02:00", weekdays: [Time.Weekday.saturday], result: true),
        (dateString: "2024-07-20T23:42:06+02:00", weekdays: [Time.Weekday.friday], result: false),
        (dateString: "2024-07-20T21:41:06+02:00", weekdays: [Time.Weekday.friday], result: false)
    ])
    func timeEqualityWithWeekday(arguments: (dateString: String, weekdays: [Time.Weekday], result: Bool)) throws {
        let date = try Date(arguments.dateString, strategy: .iso8601)
        let event = HomeEvent.time(date: date)

        let time = Time(hour: 23, minute: 42, weekdays: arguments.weekdays)
        #expect(time.isEqual(event) == arguments.result, Comment(stringLiteral: arguments.dateString))
    }
}
