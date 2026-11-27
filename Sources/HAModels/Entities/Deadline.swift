//
//  Deadline.swift
//  HAModels
//

import Foundation

/// The state of a deadline (glossary: Fensterschließzeit): none, running until a moment, or overdue.
///
/// An overdue deadline keeps the moment it ran until, so the same deadline always reports the same value
/// and a replay after a restart is no change.
public enum Deadline: Hashable, Sendable {
    case none
    case running(until: Date)
    case overdue(since: Date)

    /// The moment the deadline runs or ran until, `nil` for none.
    public var end: Date? {
        switch self {
        case .none: nil
        case .running(let until): until
        case .overdue(let since): since
        }
    }

    /// The case as stored in the text column.
    public var caseName: String {
        switch self {
        case .none: "none"
        case .running: "running"
        case .overdue: "overdue"
        }
    }

    public var isOverdue: Bool {
        if case .overdue = self { true } else { false }
    }

    /// How a deadline reads in a list: the case and, when it has one, the time of day of its end.
    public var displayText: String {
        switch self {
        case .none: "No deadline"
        case .running(let until): "Until \(until.formatted(date: .omitted, time: .shortened))"
        case .overdue(let since): "Overdue since \(since.formatted(date: .omitted, time: .shortened))"
        }
    }

    /// The generic text form `"<case> <seconds since 1970>"`, `"none"` without an end.
    public var text: String {
        guard let end else { return caseName }
        return "\(caseName) \(end.timeIntervalSince1970)"
    }

    /// The deadline from its case and end as the narrow storage keeps them: the text for the case, the number for the end.
    public init?(caseName: String, end: Double?) {
        switch (caseName, end) {
        case ("none", _): self = .none
        case ("running", let end?): self = .running(until: Date(timeIntervalSince1970: end))
        case ("overdue", let end?): self = .overdue(since: Date(timeIntervalSince1970: end))
        default: return nil
        }
    }

    public init?(text: String) {
        let parts = text.split(separator: " ")
        switch parts.count {
        case 1: self.init(caseName: String(parts[0]), end: nil)
        case 2:
            guard let end = Double(parts[1]) else { return nil }
            self.init(caseName: String(parts[0]), end: end)
        default: return nil
        }
    }
}
