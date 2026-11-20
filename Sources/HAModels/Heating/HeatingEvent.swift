//
//  HeatingEvent.swift
//  HAModels
//

import Foundation

/// What kind of event a pin of the Heizung detail stands for (glossary: heating event).
public enum HeatingEventSource: String, Sendable, Codable, CaseIterable, Equatable {
    case plan, window, fireplace, observed, system
}

extension HeatingEventSource {
    /// Whether `item`, a state of the contact entity of this source, says open: the window contact is open, the
    /// fireplace switch is on. An item without the value counts as closed. The one place that reads "open".
    public func isOpen(_ item: EntityStorageItem) -> Bool {
        switch self {
        case .fireplace:
            return item.isDeviceOn ?? false
        default:
            return item.isContactOpen ?? false
        }
    }
}

/// Something that happened in a room: a pin above the chart, with an area when it had a duration.
public struct HeatingEvent: Identifiable, Sendable, Codable, Equatable {
    public let source: HeatingEventSource
    public let title: String
    /// Why it happened, in a sentence; shown in the popover or the inline card.
    public let reason: String
    /// The real start, also when it lies before the range.
    public let start: Date
    /// The real end; `nil` for a moment or while it lasts.
    public let end: Date?
    /// Where the pin sits: the start, or the start of the range when the event began before it.
    public let pin: Date

    /// Source, start and reason: two radiators changed by hand in the same second are two events.
    public var id: String { "\(source.rawValue)-\(Int(start.timeIntervalSince1970))-\(reason)" }

    /// Whether the event is drawn as an area: window and fireplace with a duration.
    public var hasDuration: Bool { source == .window || source == .fireplace }

    public init(source: HeatingEventSource, title: String, reason: String, start: Date, end: Date? = nil, pin: Date? = nil) {
        self.source = source
        self.title = title
        self.reason = reason
        self.start = start
        self.end = end
        self.pin = pin ?? start
    }
}
