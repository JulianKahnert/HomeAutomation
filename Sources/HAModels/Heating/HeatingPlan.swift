//
//  HeatingPlan.swift
//  HAModels
//

import Foundation

/// A time of day with a target temperature (glossary: switch point).
public struct SwitchPoint: Sendable, Codable, Equatable {
    public let hour: Int
    public let minute: Int
    public let targetInC: Double

    public init(hour: Int, minute: Int = 0, targetInC: Double) {
        self.hour = hour
        self.minute = minute
        self.targetInC = targetInC
    }

    var minuteOfDay: Int { hour * 60 + minute }
}

/// The schedule of a room: switch points per weekday group (glossary: plan).
///
/// A weekday that belongs to several groups follows the first one; a weekday that belongs to none has
/// no switch points, so the target of the last earlier switch point holds through it.
public struct HeatingPlan: Sendable, Codable, Equatable {
    /// The switch points of a group of weekdays, e.g. Monday to Friday.
    public struct Schedule: Sendable, Codable, Equatable {
        public let weekdays: [Time.Weekday]
        public let switchPoints: [SwitchPoint]

        public init(weekdays: [Time.Weekday], switchPoints: [SwitchPoint]) {
            self.weekdays = weekdays
            self.switchPoints = switchPoints.sorted { $0.minuteOfDay < $1.minuteOfDay }
        }
    }

    public let schedules: [Schedule]

    public init(_ schedules: [Schedule]) {
        self.schedules = schedules
    }

    /// The switch point that starts exactly in the minute of `date`, if any.
    public func switchPoint(at date: Date, calendar: Calendar = .current) -> SwitchPoint? {
        let minuteOfDay = Self.minuteOfDay(of: date, calendar: calendar)
        return switchPoints(on: date, calendar: calendar).first { $0.minuteOfDay == minuteOfDay }
    }

    /// The plan target at `date`: the target of the last switch point at or before it, wrapping into
    /// earlier days; `nil` for a plan without switch points.
    public func planTarget(at date: Date, calendar: Calendar = .current) -> Double? {
        let minuteOfDay = Self.minuteOfDay(of: date, calendar: calendar)
        if let current = switchPoints(on: date, calendar: calendar).last(where: { $0.minuteOfDay <= minuteOfDay }) {
            return current.targetInC
        }
        for daysBack in 1...7 {
            guard let day = calendar.date(byAdding: .day, value: -daysBack, to: date),
                  let last = switchPoints(on: day, calendar: calendar).last else { continue }
            return last.targetInC
        }
        return nil
    }

    private func switchPoints(on date: Date, calendar: Calendar) -> [SwitchPoint] {
        guard let weekday = Time.Weekday(rawValue: calendar.component(.weekday, from: date)) else { return [] }
        return schedules.first { $0.weekdays.contains(weekday) }?.switchPoints ?? []
    }

    private static func minuteOfDay(of date: Date, calendar: Calendar) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }
}

/// Values every room shares unless it overrides them: the standard plan and the delays (glossary: global
/// configuration). Built once in the configuration repository and passed to every room.
public struct HeatingConfiguration: Sendable, Codable, Equatable {
    /// The plan of rooms without a plan of their own.
    public let standardPlan: HeatingPlan
    /// How long a window has to stay open before its room goes off. Not used before window-off exists.
    public let windowDelay: TimeInterval

    public init(standardPlan: HeatingPlan, windowDelay: TimeInterval = 10) {
        self.standardPlan = standardPlan
        self.windowDelay = windowDelay
    }
}
