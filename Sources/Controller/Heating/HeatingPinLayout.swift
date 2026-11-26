//
//  HeatingPinLayout.swift
//  ControllerFeatures
//
//  Pure choice and layout of the event pins above the chart: at most two rows, a "+n" pin for the rest
//

import CoreGraphics
import Foundation
import HAModels

enum HeatingPinLayout {
    /// One badge above the chart: a single event or, when the rows are full, a "+n" pin holding several.
    struct Slot: Equatable, Identifiable {
        let x: CGFloat
        let row: Int
        var events: [HeatingEvent]

        var id: String { (events.count > 1 ? "group-" : "") + events[0].id }
        var badge: String? { events.count > 1 ? "+\(events.count)" : nil }

        func contains(_ pinId: String?) -> Bool {
            guard let pinId else { return false }
            return pinId == id || events.contains { $0.id == pinId }
        }
    }

    /// The events drawn as pins: plan switches only up to 24 h, over a week they would bury the rest.
    static func pins(_ events: [HeatingEvent], range: HeatingRange) -> [HeatingEvent] {
        events.filter { range != .week || $0.source != .plan }
    }

    /// The events drawn as areas: those with a duration.
    static func areas(_ events: [HeatingEvent]) -> [HeatingEvent] {
        events.filter(\.hasDuration)
    }

    /// Each pin takes the first row whose last pin is at least `pinWidth` away. With all rows taken, it joins
    /// the last pin of the last row, which becomes a "+n" pin. `events` must be sorted by pin position.
    static func slots(_ events: [HeatingEvent], in domain: ClosedRange<Date>, plotWidth: CGFloat, pinWidth: CGFloat, rows: Int) -> [Slot] {
        let span = max(domain.upperBound.timeIntervalSince(domain.lowerBound), 1)
        var slots: [Slot] = []
        var lastInRow: [Int] = []
        for event in events {
            let x = CGFloat(event.pin.timeIntervalSince(domain.lowerBound) / span) * plotWidth
            if let row = lastInRow.firstIndex(where: { x - slots[$0].x >= pinWidth }) {
                slots.append(Slot(x: x, row: row, events: [event]))
                lastInRow[row] = slots.count - 1
            } else if lastInRow.count < rows {
                slots.append(Slot(x: x, row: lastInRow.count, events: [event]))
                lastInRow.append(slots.count - 1)
            } else {
                slots[lastInRow[rows - 1]].events.append(event)
            }
        }
        return slots
    }
}
