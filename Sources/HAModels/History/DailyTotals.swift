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

    /// Time-weighted mean and maximum per day; each sample holds until the next one, the newest until `end`.
    /// Days without any covered time are left out.
    public static func dailyStats(_ samples: [(date: Date, value: Double)], days: [Date], end: Date, calendar: Calendar) -> [(day: Date, max: Double, mean: Double)] {
        let sorted = samples.sorted { $0.date < $1.date }
        let segments = sorted.indices.compactMap { index -> (interval: DateInterval, value: Double)? in
            let until = index + 1 < sorted.count ? sorted[index + 1].date : end
            guard sorted[index].date < until else { return nil }
            return (DateInterval(start: sorted[index].date, end: until), sorted[index].value)
        }
        return days.compactMap { day in
            guard let dayInterval = calendar.dateInterval(of: .day, for: day) else { return nil }
            let parts = segments.compactMap { segment in
                segment.interval.intersection(with: dayInterval).map { (duration: $0.duration, value: segment.value) }
            }.filter { $0.duration > 0 }
            let total = parts.reduce(0) { $0 + $1.duration }
            guard total > 0, let max = parts.map(\.value).max() else { return nil }
            return (day, max, parts.reduce(0) { $0 + $1.duration * $1.value } / total)
        }
    }

    /// Start-of-day dates of the last `count` days, oldest first, ending with the day of `end`.
    public static func days(count: Int, endingAt end: Date, calendar: Calendar) -> [Date] {
        (0..<count).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: calendar.startOfDay(for: end)) }
    }
}
