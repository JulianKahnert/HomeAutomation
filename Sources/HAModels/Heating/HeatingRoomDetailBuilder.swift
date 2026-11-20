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

        public init(name: String, temperatureId: EntityId, valvePositionId: EntityId) {
            self.name = name
            self.temperatureId = temperatureId
            self.valvePositionId = valvePositionId
        }
    }

    public let placeId: String
    public let name: String
    public let radiators: [Radiator]
    public var roomSensor: EntityId?
    /// Fallback for plan targets before the first plan write in a range.
    public var plan: HeatingPlan?
    /// Whether the room lists the fireplace as a contact (glossary: fireplace mode).
    public var followsFireplace: Bool

    public init(placeId: String, name: String, radiators: [Radiator], roomSensor: EntityId?, plan: HeatingPlan?, followsFireplace: Bool = false) {
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
    private let writes: any HeatingWriteRepository
    private let now: @Sendable () -> Date
    private let sensorFailureLimit: TimeInterval
    private let calendar: Calendar

    /// - Parameter sensorFailureLimit: A reading older than this no longer counts: the grid shows a gap.
    ///   Rows are only stored when a value changed, so this is the only way to see a silent sensor.
    public init(storage: any StorageRepository,
                writes: any HeatingWriteRepository,
                now: @escaping @Sendable () -> Date = { Date() },
                sensorFailureLimit: TimeInterval = 6 * 3_600,
                calendar: Calendar = .current) {
        self.storage = storage
        self.writes = writes
        self.now = now
        self.sensorFailureLimit = sensorFailureLimit
        self.calendar = calendar
    }

    public func detail(for room: HeatingRoomSources, range: HeatingRange) async throws -> HeatingRoomDetail {
        let end = now()
        let start = end.addingTimeInterval(-range.duration)
        let grid = stride(from: start, through: end, by: range.step).map { $0 }

        let thermostatTemps = try await room.radiators.asyncMap { try await series($0.temperatureId, from: start, to: end) { $0.temperatureInC?.value } }
        let valves = try await room.radiators.asyncMap { try await series($0.valvePositionId, from: start, to: end) { $0.valvePositionPercent.map(Double.init) } }
        let sensorTemps = try await room.roomSensor.asyncFlatMap { try await series($0, from: start, to: end) { $0.temperatureInC?.value } }
        let planWrites = try await writes.writes(placeId: room.placeId, startDate: nil, endDate: end)
            .filter { $0.planTargetInC != nil }
            .sorted { $0.timestamp < $1.timestamp }
        // `startDate: nil` also returns what was written before the window, so a target set yesterday holds.

        let samples = grid.map { date -> HeatingSample in
            let ist: Double?
            if let sensorTemps {
                ist = sensorTemps.value(at: date, limit: sensorFailureLimit)
            } else {
                let values = thermostatTemps.compactMap { $0.value(at: date, limit: sensorFailureLimit) }
                ist = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
            }
            let planned = planWrites.last { $0.timestamp <= date }?.planTargetInC ?? room.plan?.planTarget(at: date, calendar: calendar)
            let valveValues = room.radiators.indices.map { index -> Double? in
                // A radiator whose own temperature went silent shows no valve either.
                if !thermostatTemps[index].isEmpty, thermostatTemps[index].value(at: date, limit: sensorFailureLimit) == nil { return nil }
                return valves[index].value(at: date, limit: nil)
            }
            return HeatingSample(date: date, ist: ist, sollPlan: planned, valves: valveValues)
        }

        let istSeries = sensorTemps.map { [$0] } ?? thermostatTemps
        return HeatingRoomDetail(placeId: room.placeId,
                                 name: room.name,
                                 range: range,
                                 istSource: room.roomSensor.map { .roomSensor($0.name) } ?? .thermostats(room.radiators.map(\.name)),
                                 radiators: room.radiators.map(\.name),
                                 samples: samples,
                                 lastIst: istSeries.compactMap { $0.points.last?.date }.max())
    }

    /// Every stored value of `entityId` in the range plus the one before it, oldest first. Pages by cursor,
    /// because seven days of a temperature exceed one page.
    private func series(_ entityId: EntityId, from start: Date, to end: Date, value: (EntityStorageItem) -> Double?) async throws -> Series {
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
        return Series(points: items.sorted { $0.timestamp < $1.timestamp }.compactMap { item in value(item).map { (item.timestamp, $0) } })
    }
}

private struct Series {
    let points: [(date: Date, value: Double)]

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
        if let limit, date.timeIntervalSince(point.date) > limit { return nil }
        return point.value
    }
}

private extension Optional {
    func asyncFlatMap<T>(_ transform: (Wrapped) async throws -> T) async rethrows -> T? {
        guard let self else { return nil }
        return try await transform(self)
    }
}
