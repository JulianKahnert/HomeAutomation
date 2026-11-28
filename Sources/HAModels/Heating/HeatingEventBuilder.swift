//
//  HeatingEventBuilder.swift
//  HAModels
//

import Foundation

/// Derives the events of a room from what the server wrote (reasons), the contacts' history (durations)
/// and the radiators' targets ("observed").
struct HeatingEventBuilder {
    let room: HeatingRoomSources
    let writes: [ActionLogItem]
    /// Stored plan targets (time and °C) of the room's plan target entity, oldest first, including the one before the range.
    let planItems: [(Date, Double)]
    /// Stored states of each contact, oldest first, including the one before the range.
    let contactItems: [EntityId: [EntityStorageItem]]
    /// Stored targets of each radiator (by name), oldest first, including the one before the range.
    let targetItems: [String: [EntityStorageItem]]
    let start: Date
    let end: Date

    /// Writes within this distance belong to one event (one automation run writes every radiator).
    private static let cluster: TimeInterval = 60
    /// A reading this soon after a write is the radiator confirming it.
    private static let echo: TimeInterval = 5

    func events() -> [HeatingEvent] {
        var found: [HeatingEvent] = []
        var covered: Set<HeatingEventSource> = []

        for contact in room.contacts {
            covered.insert(contact.source)
            found += intervals(of: contact)
        }
        for reason in [HeatingWriteReason.plan, .system, .window, .fireplace] {
            if let source = HeatingEventSource(rawValue: reason.rawValue), covered.contains(source) { continue }
            found += Self.clusters(writes.filter { $0.reason == reason }).compactMap { pointEvent(reason, $0) }
        }
        found += observed()
        return found
            .filter { ($0.end ?? $0.start) >= start && $0.start <= end }
            .map { HeatingEvent(source: $0.source, title: $0.title, reason: $0.reason, start: $0.start, end: $0.end, pin: max($0.start, start)) }
            .sorted { ($0.pin, $0.start) < ($1.pin, $1.start) }
    }

    // MARK: Contacts

    private func intervals(of contact: HeatingRoomSources.Contact) -> [HeatingEvent] {
        var result: [HeatingEvent] = []
        var openedAt: Date?
        let items = (contactItems[contact.entityId] ?? []).sorted { $0.timestamp < $1.timestamp }
        func close(at closedAt: Date?, by origin: Origin? = nil) {
            guard let opened = openedAt else { return }
            openedAt = nil
            if let event = intervalEvent(contact, from: opened, to: closedAt, closedBy: origin) { result.append(event) }
        }
        for item in items {
            let isOpen = contact.source.isOpen(item)
            if isOpen, openedAt == nil { openedAt = item.timestamp } else if !isOpen { close(at: item.timestamp, by: item.origin) }
        }
        close(at: nil)
        return result
    }

    private func intervalEvent(_ contact: HeatingRoomSources.Contact, from opened: Date, to closed: Date?, closedBy origin: Origin?) -> HeatingEvent? {
        let last = closed ?? end
        switch contact.source {
        case .window:
            // Shorter than the window delay the room does not react: only an opening the server wrote for counts.
            let acted = writes.contains { $0.reason == .window && $0.timestamp >= opened.addingTimeInterval(-1) && $0.timestamp <= last.addingTimeInterval(120) }
            guard acted else { return nil }
            let reason = closed.map { "Fenster „\(contact.name)“ war \(Self.duration($0.timeIntervalSince(opened))) offen, die Heizkörper waren aus." }
                ?? "Fenster „\(contact.name)“ ist offen, die Heizkörper sind aus."
            return HeatingEvent(source: .window, title: "Fenster offen", reason: reason, start: opened, end: closed)
        default:
            var reason = "Kamin an: die Heizkörper der Räume am Kamin sind aus."
            var title = "Kamin an"
            if let closed {
                // the history says who switched it off: the server's own end after the maximum duration, or the app
                if origin == .server {
                    reason = "Der Kamin wurde nach \(Self.duration(closed.timeIntervalSince(opened))) per Zeitablauf ausgeschaltet; dazu kam die Benachrichtigung „Kamin aus“."
                    title = "Kamin aus (Zeitablauf)"
                } else {
                    reason = "Kamin war \(Self.duration(closed.timeIntervalSince(opened))) an: die Heizkörper waren aus."
                }
            }
            return HeatingEvent(source: .fireplace, title: title, reason: reason, start: opened, end: closed)
        }
    }

    // MARK: Writes

    private static func clusters(_ writes: [ActionLogItem]) -> [[ActionLogItem]] {
        var result: [[ActionLogItem]] = []
        for write in writes.sorted(by: { $0.timestamp < $1.timestamp }) {
            if let first = result.last?.first, write.timestamp.timeIntervalSince(first.timestamp) <= cluster {
                result[result.count - 1].append(write)
            } else {
                result.append([write])
            }
        }
        return result
    }

    /// The plan target the room had when a cluster began: the last stored plan-target state at that time.
    /// The plan write reports the target a moment before it writes the radiators, hence the small margin.
    private func planTarget(at date: Date) -> Double? {
        planItems.planTarget(at: date, margin: Self.echo)
    }

    private func pointEvent(_ reason: HeatingWriteReason, _ cluster: [ActionLogItem]) -> HeatingEvent? {
        guard let first = cluster.first else { return nil }
        let planTarget = planTarget(at: first.timestamp) ?? cluster.compactMap(\.targetTemperatureInC).first
        let off = cluster.contains { $0.isActive == false }
        let names = Set(cluster.map(\.entityId.name)).sorted().joined(separator: ", ")
        let target = planTarget.map { Self.degrees($0) }
        switch reason {
        case .plan:
            return HeatingEvent(source: .plan, title: target.map { "Plan \($0)" } ?? "Plan",
                                reason: "Planwechsel: \(names) auf \(target ?? "den Planwert") gesetzt.", start: first.timestamp)
        case .system:
            return HeatingEvent(source: .system, title: "System",
                                reason: off ? "Der Server hat \(names) ausgeschaltet (Deploy oder Zeitablauf)." : "Der Server hat \(names)\(target.map { " auf \($0)" } ?? "") gesetzt (Deploy oder Zeitablauf).",
                                start: first.timestamp)
        case .window:
            return HeatingEvent(source: .window, title: off ? "Fenster offen" : "Fenster zu",
                                reason: off ? "Ein Fenster war offen: \(names) ausgeschaltet." : "Das Fenster ist zu: \(names) zurück auf den Plan.", start: first.timestamp)
        case .fireplace:
            return HeatingEvent(source: .fireplace, title: off ? "Kamin an" : "Kamin aus",
                                reason: off ? "Der Kamin brennt: \(names) ausgeschaltet." : "Der Kamin ist aus: \(names) zurück auf den Plan.", start: first.timestamp)
        }
    }

    // MARK: Observed

    private func observed() -> [HeatingEvent] {
        var result: [HeatingEvent] = []
        let targetWrites = writes.filter { $0.targetTemperatureInC != nil }
        for radiator in room.radiators {
            let own = targetWrites.filter { $0.entityId.name == radiator.name }
            var lastWrite: ActionLogItem?
            var reported: Double?
            for item in (targetItems[radiator.name] ?? []).sorted(by: { $0.timestamp < $1.timestamp }) {
                guard let value = item.targetTemperatureInC else { continue }
                let current = own.last { $0.timestamp <= item.timestamp }
                if current?.id != lastWrite?.id { reported = nil }
                lastWrite = current
                guard let current, let written = current.targetTemperatureInC,
                      item.timestamp.timeIntervalSince(current.timestamp) > Self.echo else { continue }
                if abs(value - written) < 0.05 {
                    reported = nil
                } else if reported != value {
                    reported = value
                    result.append(HeatingEvent(source: .observed, title: "Von Hand: \(Self.degrees(value))",
                                               reason: "\(radiator.name) steht auf \(Self.degrees(value)) statt \(Self.degrees(written)), dem Wert, den der Server zuletzt geschrieben hat. Der Server greift nicht ein; es gilt bis zum nächsten Schaltpunkt.",
                                               start: item.timestamp))
                }
            }
        }
        return result
    }

    // MARK: Text

    static func degrees(_ value: Double) -> String {
        String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",") + " °C"
    }

    static func duration(_ interval: TimeInterval) -> String {
        let minutes = max(Int((interval / 60).rounded()), 1)
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
    }
}
