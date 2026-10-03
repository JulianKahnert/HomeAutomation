//
//  StateIntervals.swift
//  HAModels
//

import Foundation

/// Turns a change log of a boolean state into the periods in which it held.
public enum StateIntervals {
    /// Periods in which `isActive` returned `true`, clipped to `start...end`.
    ///
    /// Items may come in any order: the server sends newest first and appends the `includePrevious`
    /// item last, which sets the state at the left edge. Items where `isActive` is `nil` are skipped,
    /// and an interval still open at the newest item is closed at `end`.
    public static func intervals(items: [EntityHistoryItem], isActive: (EntityHistoryItem) -> Bool?, from start: Date, to end: Date) -> [DateInterval] {
        var result: [DateInterval] = []
        var activeSince: Date?
        let close = { (since: Date, until: Date) in
            let clippedStart = max(since, start)
            let clippedEnd = min(until, end)
            if clippedStart < clippedEnd {
                result.append(DateInterval(start: clippedStart, end: clippedEnd))
            }
        }
        for item in items.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard let active = isActive(item) else { continue }
            if active, activeSince == nil {
                activeSince = item.timestamp
            } else if !active, let since = activeSince {
                close(since, item.timestamp)
                activeSince = nil
            }
        }
        if let activeSince {
            close(activeSince, end)
        }
        return result
    }

    /// Periods within `range` in which the sun is below the horizon; days without sunrise or sunset are skipped.
    public static func nights(in range: DateInterval, latitude: Double, longitude: Double, calendar: Calendar = .current) -> [DateInterval] {
        var daylight: [DateInterval] = []
        var day = calendar.startOfDay(for: range.start)
        while day < range.end {
            if let schedule = Sun.schedule(latitude: latitude, longitude: longitude, date: day.addingTimeInterval(12 * 3600), calendar: calendar, timeZone: calendar.timeZone),
               let sunrise = schedule.sunrise?.date, let sunset = schedule.sunset?.date, sunrise < sunset {
                daylight.append(DateInterval(start: sunrise, end: sunset))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        var nights: [DateInterval] = []
        var cursor = range.start
        for interval in daylight + [DateInterval(start: range.end, duration: 0)] {
            let end = min(interval.start, range.end)
            if cursor < end {
                nights.append(DateInterval(start: cursor, end: end))
            }
            cursor = max(cursor, interval.end)
        }
        return nights
    }
}
