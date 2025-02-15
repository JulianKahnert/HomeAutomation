//
//  Time.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 20.07.24.
//

import Foundation

public struct Time: Sendable, Codable {
    struct TimeData: Codable {
        let hour: Int
        let minute: Int
        let weekdays: [Weekday]
    }

    enum Kind: Codable {
        case absolute(TimeData)
        case sunrise
        case sunset
    }

    let kind: Kind

    public init(hour: Int, minute: Int, weekdays: [Weekday] = []) {
        kind = .absolute(.init(hour: hour, minute: minute, weekdays: weekdays))
    }

    private init(kind: Kind) {
        self.kind = kind
    }

    public static func sunrise() -> Self { .init(kind: .sunrise) }
    public static func sunset() -> Self { .init(kind: .sunset) }

    public func isEqual(_ event: HomeEvent) -> Bool {
        switch kind {
        case .absolute(let timeData):
            guard case .time(let date) = event else { return false }
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: date)
            let minute = calendar.component(.minute, from: date)

            if timeData.weekdays.isEmpty {
                return hour == timeData.hour && minute == timeData.minute
            } else {
                return Self.isDate(date, in: timeData.weekdays) && hour == timeData.hour && minute == timeData.minute
            }
        case .sunrise:
            guard case .sunrise = event else { return false }
            return true
        case .sunset:
            guard case .sunset = event else { return false }
            return true
        }
    }

    public static func isDate(_ date: Date, in weekdays: [Weekday]) -> Bool {
        assert(!weekdays.isEmpty, "Weekdays should not be empty")

        // Weekday: 1 = Sunday, 2 = Monday, ..., 7 = Saturday
        let weekday = Calendar.current.component(.weekday, from: date)

        return weekdays.map(\.rawValue).contains(weekday)
    }

    public enum Weekday: Int, Sendable, Codable {
        case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday
    }
}
