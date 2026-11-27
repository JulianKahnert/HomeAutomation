//
//  BacklogReporter.swift
//  Shared
//

import Foundation

/// The bookkeeping both the automation lanes and the event loop need for "how old is the oldest unfinished item, and
/// say so once per backlog".
public struct BacklogReporter: Sendable {
    private var reported = false

    public init() {}

    /// The age of the oldest unfinished item; 0 when there is none.
    public static func age(ofOldest oldest: Date?, now: Date) -> TimeInterval {
        guard let oldest else { return 0 }
        return max(0, now.timeIntervalSince(oldest))
    }

    /// The age to report when it is above `limit` and this backlog was not reported yet; `nil` otherwise. The backlog
    /// is reported again only after it has drained (age 0).
    public mutating func report(age: TimeInterval, olderThan limit: TimeInterval) -> TimeInterval? {
        guard age > limit else {
            if age == 0 { reported = false }
            return nil
        }
        guard !reported else { return nil }
        reported = true
        return age
    }
}
