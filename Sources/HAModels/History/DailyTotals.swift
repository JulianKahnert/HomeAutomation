//
//  DailyTotals.swift
//  HAModels
//

import Foundation

/// Per-day aggregation of intervals and events for bar charts.
public enum DailyTotals {
    /// Time covered by `intervals` on each day; `days` are the start-of-day dates to report.
    public static func dailyTotals(_ intervals: [DateInterval], days: [Date], calendar: Calendar) -> [(day: Date, duration: TimeInterval)] {
        days.map { day in
            guard let dayInterval = calendar.dateInterval(of: .day, for: day) else { return (day, 0) }
            let duration = intervals.reduce(0) { sum, interval in
                sum + (interval.intersection(with: dayInterval)?.duration ?? 0)
            }
            return (day, duration)
        }
    }

    /// Number of `dates` falling on each of `days`.
    public static func countsPerDay(_ dates: [Date], days: [Date], calendar: Calendar) -> [(day: Date, count: Int)] {
        days.map { day in
            (day, dates.count { calendar.isDate($0, inSameDayAs: day) })
        }
    }
}
