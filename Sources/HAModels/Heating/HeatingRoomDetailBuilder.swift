//
//  HeatingRoomDetailBuilder.swift
//  HAModels
//

import Foundation

/// What the aggregation needs to know about a room: its radiators' entities, the optional room sensor
/// and the plan. Built from the room's heating automation.
public struct HeatingRoomSources: Sendable, Equatable {
    public struct Radiator: Sendable, Equatable {
        public let name: String
        public let temperatureId: EntityId
        public let valvePositionId: EntityId
        /// The radiator's target temperature; needed to see manual changes ("observed").
        public let targetTemperatureId: EntityId?

        public init(name: String, temperatureId: EntityId, valvePositionId: EntityId, targetTemperatureId: EntityId? = nil) {
            self.name = name
            self.temperatureId = temperatureId
            self.valvePositionId = valvePositionId
            self.targetTemperatureId = targetTemperatureId
        }
    }

    /// A contact of the room whose history gives window and fireplace events a duration.
    public struct Contact: Sendable, Equatable {
        /// `.window` or `.fireplace`.
        public let source: HeatingEventSource
        public let name: String
        public let entityId: EntityId

        public init(source: HeatingEventSource, name: String, entityId: EntityId) {
            self.source = source
            self.name = name
            self.entityId = entityId
        }
    }

    public let placeId: String
    public let name: String
    /// The label under the room's bar in the overview; `nil` derives it from `name`.
    public var shortName: String?
    public let radiators: [Radiator]
    public var roomSensor: EntityId?
    /// The plan target of the room as a server-owned entity: `RoomHeating` reports it at every switch point, its
    /// history is the plan line.
    public var planTargetId: EntityId { Self.planTargetId(placeId: placeId) }

    public static func planTargetId(placeId: String) -> EntityId {
        .serverOwned(name: placeId, characteristic: .targetTemperature)
    }

    /// Fallback for plan targets before the first plan target was reported.
    public var plan: HeatingPlan?
    /// Whether the room lists the fireplace as a contact (glossary: fireplace mode).
    public var followsFireplace: Bool
    public var contacts: [Contact]

    public init(placeId: String, name: String, radiators: [Radiator], roomSensor: EntityId?, plan: HeatingPlan?, followsFireplace: Bool = false,
                contacts: [Contact] = []) {
        self.contacts = contacts
        self.followsFireplace = followsFireplace
        self.placeId = placeId
        self.name = name
        self.radiators = radiators
        self.roomSensor = roomSensor
        self.plan = plan
    }
}

/// Builds the time grid of a room for the room endpoint: actual value, plan target and valves, each
/// resampled as "last value at or before the grid point".
public struct HeatingRoomDetailBuilder: Sendable {
    private let storage: any StorageRepository
    private let journal: any JournalStore
    private let now: @Sendable () -> Date
    private let sensorFailureLimit: TimeInterval
    private let lastReport: @Sendable (EntityId) async -> Date?
    private let calendar: Calendar

    /// The writes the events look at reach back at most this far before the range: an open window or a burning
    /// fireplace that began earlier still shows, an old "previous" state of a quiet contact does not load months.
    static let writeLookback: TimeInterval = 24 * 3_600

    /// - Parameters:
    ///   - sensorFailureLimit: A reading older than this no longer counts: the grid shows a gap.
    ///     Rows are only stored when a value changed, so the limit counts from the later of the last change and the
    ///     last report: an unchanged value that still reports shows no gap, a silent sensor does.
    ///   - lastReport: When an entity last reported (stored per entity, written at most every five minutes); `nil` until the entity has reported once.
    public init(storage: any StorageRepository,
                journal: any JournalStore,
                now: @escaping @Sendable () -> Date = { Date() },
                sensorFailureLimit: TimeInterval = 6 * 3_600,
                lastReport: @escaping @Sendable (EntityId) async -> Date? = { _ in nil },
                calendar: Calendar = .current) {
        self.storage = storage
        self.journal = journal
        self.now = now
        self.sensorFailureLimit = sensorFailureLimit
        self.lastReport = lastReport
        self.calendar = calendar
    }

    /// - Parameter includeEvents: `false` leaves `events` empty and skips the contact and target histories they
    ///   need; the overview only reads the samples.
    public func detail(for room: HeatingRoomSources, range: HeatingRange, includeEvents: Bool = true) async throws -> HeatingRoomDetail {
        let end = now()
        let start = end.addingTimeInterval(-range.duration)
        let grid = stride(from: start, through: end, by: range.step).map { $0 }

        let thermostatTemps = try await room.radiators.asyncMap { try await series($0.temperatureId, from: start, to: end) { $0.temperatureInC?.value } }
        let valves = try await room.radiators.asyncMap { try await series($0.valvePositionId, from: start, to: end) { $0.valvePositionPercent.map(Double.init) } }
        let sensorTemps = try await room.roomSensor.asyncFlatMap { try await series($0, from: start, to: end) { $0.temperatureInC?.value } }
        let planItems = try await items(room.planTargetId, from: start, to: end).compactMap { item in item.targetTemperatureInC.map { (item.timestamp, $0) } }
        var contactItems: [EntityId: [EntityStorageItem]] = [:]
        var targetItems: [String: [EntityStorageItem]] = [:]
        if includeEvents {
            for contact in room.contacts {
                contactItems[contact.entityId] = try await items(contact.entityId, from: start, to: end)
            }
            for radiator in room.radiators {
                if let id = radiator.targetTemperatureId { targetItems[radiator.name] = try await items(id, from: start, to: end) }
            }
        }
        // Events need the writes from the earliest state they look at: an interval that began before the range
        // starts with the stored state before it, but no further back than `writeLookback`.
        let earliest = (contactItems.values.flatMap { $0 } + targetItems.values.flatMap { $0 }).map(\.timestamp).min() ?? start
        let firstWrite = max(min(start, earliest), start.addingTimeInterval(-Self.writeLookback))
        let allWrites = try await journal.heatingWrites(placeId: room.placeId, startDate: firstWrite, endDate: end)

        let samples = grid.map { date -> HeatingSample in
            let ist: Double?
            if let sensorTemps {
                ist = sensorTemps.value(at: date, limit: sensorFailureLimit)
            } else {
                let values = thermostatTemps.compactMap { $0.value(at: date, limit: sensorFailureLimit) }
                ist = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
            }
            let planned = planItems.planTarget(at: date) ?? room.plan?.planTarget(at: date, calendar: calendar)
            let valveValues = room.radiators.indices.map { index -> Double? in
                // A radiator whose own temperature went silent shows no valve either.
                if !thermostatTemps[index].isEmpty, thermostatTemps[index].value(at: date, limit: sensorFailureLimit) == nil { return nil }
                return valves[index].value(at: date, limit: nil)
            }
            return HeatingSample(date: date, ist: ist, sollPlan: planned, valves: valveValues)
        }

        // Only what reached a radiator is an event: the journal rows are the executed commands.
        let events = includeEvents
            ? HeatingEventBuilder(room: room, writes: allWrites, planItems: planItems, contactItems: contactItems, targetItems: targetItems,
                                  start: start, end: end).events()
            : []

        let istSeries = sensorTemps.map { [$0] } ?? thermostatTemps
        return HeatingRoomDetail(placeId: room.placeId,
                                 name: room.name,
                                 range: range,
                                 istSource: room.roomSensor.map { .roomSensor($0.name) } ?? .thermostats(room.radiators.map(\.name)),
                                 radiators: room.radiators.map(\.name),
                                 samples: samples,
                                 lastIst: istSeries.compactMap { $0.points.last?.date }.max(),
                                 events: events)
    }

    /// Every stored value of `entityId` in the range plus the one before it, oldest first. Pages by cursor,
    /// because seven days of a temperature exceed one page.
    private func series(_ entityId: EntityId, from start: Date, to end: Date, value: (EntityStorageItem) -> Double?) async throws -> Series {
        let all = try await items(entityId, from: start, to: end)
        return Series(points: all.compactMap { item in value(item).map { (item.timestamp, $0) } }, lastReport: await lastReport(entityId))
    }

    /// The stored states of `entityId` in the range plus the one before it, oldest first.
    private func items(_ entityId: EntityId, from start: Date, to end: Date) async throws -> [EntityStorageItem] {
        let pageSize = 1_000
        var items: [EntityStorageItem] = []
        var cursor: Date?
        while true {
            let page = try await storage.getHistory(for: entityId, startDate: start, endDate: end.addingTimeInterval(1), cursor: cursor, limit: pageSize)
            items += page
            guard page.count == pageSize, let oldest = page.last else { break }
            cursor = oldest.timestamp
        }
        if let previous = try await storage.getHistory(for: entityId, startDate: nil, endDate: start, cursor: nil, limit: 1).first {
            items.append(previous)
        }
        return items.sorted { $0.timestamp < $1.timestamp }
    }
}

private struct Series {
    let points: [(date: Date, value: Double)]
    /// When the entity last reported; keeps the last point alive while the value is unchanged.
    var lastReport: Date?

    var isEmpty: Bool { points.isEmpty }

    /// The last value at or before `date`; `nil` when there is none or it is older than `limit`.
    func value(at date: Date, limit: TimeInterval?) -> Double? {
        var low = 0, high = points.count
        while low < high {
            let mid = (low + high) / 2
            if points[mid].date <= date { low = mid + 1 } else { high = mid }
        }
        guard low > 0 else { return nil }
        let point = points[low - 1]
        if let limit {
            let isLast = low == points.count
            let alive = isLast ? max(point.date, lastReport ?? point.date) : point.date
            if date.timeIntervalSince(alive) > limit { return nil }
        }
        return point.value
    }
}

private extension Optional {
    func asyncFlatMap<T>(_ transform: (Wrapped) async throws -> T) async rethrows -> T? {
        guard let self else { return nil }
        return try await transform(self)
    }
}

extension [(Date, Double)] {
    /// The last stored plan target at `date`; `margin` lets a state that was stored a moment later still count.
    func planTarget(at date: Date, margin: TimeInterval = 0) -> Double? {
        last { $0.0 <= date.addingTimeInterval(margin) }?.1
    }
}
