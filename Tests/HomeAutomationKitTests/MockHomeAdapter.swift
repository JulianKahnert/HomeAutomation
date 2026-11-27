//
//  MockHomeAdapter.swift
//
//
//  Created by Julian Kahnert on 02.07.24.
//

import Distributed
import Foundation
import HAModels
import Logging

@HomeManagerActor
final class MockHomeAdapter: @unchecked Sendable, HomeManagable {

    let entityStream: AsyncStream<EntityStorageItem>
    let entityStreamContinuation: AsyncStream<EntityStorageItem>.Continuation

    var storageItems: [EntityStorageItem] = []
    var health = HomeKitHealth.healthy
    /// Every upkeep step the facade was asked to run.
    var upkeepSteps: [StorageUpkeepStep] = []
    private let log = Logger(label: "MockHomeAdapter")
    private var traceMap: [String: Int] = [:]
    /// Every action `perform` ran, with the heating context it ran in.
    var performedActions: [(action: HomeManagableAction, heating: HeatingWriteContext.Context?)] = []
    /// Every action `perform` ran, in order, for a test that waits for one; it has a single reader.
    let performedActionStream: AsyncStream<HomeManagableAction>
    private let performedActionContinuation: AsyncStream<HomeManagableAction>.Continuation

    init() {
        let (entityStream, entityStreamContinuation) = AsyncStream.makeStream(of: EntityStorageItem.self, bufferingPolicy: .unbounded)
        self.entityStream = entityStream
        self.entityStreamContinuation = entityStreamContinuation
        (performedActionStream, performedActionContinuation) = AsyncStream.makeStream(of: HomeManagableAction.self)
    }

    func perform(_ action: HomeManagableAction) async {

        let item = storageItems.first(where: { $0.entityId == action.entityId })
        performedActions.append((action, HeatingWriteContext.current))
        performedActionContinuation.yield(action)
        if let context = HeatingWriteContext.current, let write = HeatingWrite(action: action, context: context) {
            heatingWrites.append(write)
        }

        switch action {
        case .turnOn:
            guard let item = try? item.get(with: log) else { break }
            let newItem = EntityStorageItem(entityId: item.entityId, timestamp: item.timestamp, motionDetected: nil, illuminance: nil, isDeviceOn: true, isContactOpen: nil, isDoorLocked: nil, stateOfCharge: nil, isHeaterActive: nil)
            storageItems.append(newItem)
             entityStreamContinuation.yield(newItem)
        case .turnOff:
            guard let item = try? item.get(with: log) else { break }
            let newItem = EntityStorageItem(entityId: item.entityId, timestamp: item.timestamp, motionDetected: nil, illuminance: nil, isDeviceOn: false, isContactOpen: nil, isDoorLocked: nil, stateOfCharge: nil, isHeaterActive: nil)
            storageItems.append(newItem)
        case .setBrightness:
            break
        case .setColorTemperature:
            break
        case .setRGB:
            break
        case .lockDoor:
            guard let item = try? item.get(with: log) else { break }
            let newItem = EntityStorageItem(entityId: item.entityId, timestamp: item.timestamp, motionDetected: nil, illuminance: nil, isDeviceOn: nil, isContactOpen: nil, isDoorLocked: true, stateOfCharge: nil, isHeaterActive: nil)
            storageItems.append(newItem)
        case .addEntityToScene:
            break
        case .setHeating(let id, let active):
            storageItems.append(EntityStorageItem(entityId: id, isHeaterActive: active))
        case .setValve:
            break
        case .setTargetTemperature(let id, let celsius):
            storageItems.append(EntityStorageItem(entityId: id, targetTemperatureInC: celsius))
        }

        let actionString: String
        switch action {
        case .turnOn:
            actionString = "turnOn"
        case .turnOff:
            actionString = "turnOff"
        case .setBrightness:
            actionString = "setBrightness"
        case .setColorTemperature:
            actionString = "setColorTemperature"
        case .setRGB:
            actionString = "setRGB"
        case .lockDoor:
            actionString = "lockDoor"
        case .addEntityToScene:
            actionString = "addEntityToScene"
        case .setHeating:
            actionString = "setHeating"
        case .setValve:
            actionString = "setValve"
        case .setTargetTemperature:
            actionString = "setTargetTemperature"
        }

        traceMap["action.\(actionString)", default: 0] += 1
    }

    func setUsedEntityIds(_ entityIds: Set<HAModels.EntityId>) async {
        traceMap["setUsedEntityIds.count:\(entityIds.count)", default: 0] += 1
    }

    /// How often `perform` ran an action, by the action's name, e.g. `"setBrightness"`.
    func actionCount(_ actionName: String) -> Int {
        traceMap["action.\(actionName)", default: 0]
    }

    func getSortedTraceMap() -> Set<String> {
        let items = traceMap.sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
        return Set(items)
    }

    func getEntityStream() async -> AsyncStream<EntityStorageItem> {
        return entityStream
    }

    func findEntity(_ entity: EntityId) async throws {
    }

    func trigger(scene sceneName: String) async {
    }

    func getCurrentEntity(with entityId: EntityId) async throws -> EntityStorageItem {
        guard let item = storageItems.last(where: { $0.entityId == entityId }) else {
            struct EntityNotFoundError: Error {}
            throw EntityNotFoundError()
        }
        return item
    }

    func getPreviousEntity(with entityId: EntityId) async throws -> EntityStorageItem? {
        let matching = storageItems.filter { $0.entityId == entityId }
        return matching.count > 1 ? matching[matching.count - 2] : nil
    }

    /// What the database holds per entity, when it differs from the world in `storageItems` (the cache
    /// after a restart carries the timestamp of the adapter's resync, the database the real one).
    var storedItems: [EntityId: EntityStorageItem] = [:]

    func getStoredEntity(with entityId: EntityId) async -> EntityStorageItem? {
        storedItems[entityId] ?? storageItems.last(where: { $0.entityId == entityId })
    }

    /// The writes the server made to radiators: seeded by a test, and every action `perform` ran in a heating context.
    var heatingWrites: [HeatingWrite] = []

    func lastHeatingWrite(of radiator: EntityId) async -> HeatingWrite? {
        heatingWrites.last { $0.placeId == radiator.placeId && $0.entityId.name == radiator.name }
    }

    /// Commands waiting to be sent again, by entity; a test seeds them.
    var queuedRetries: [EntityId: HomeManagableAction] = [:]

    func queuedRetry(of entityId: EntityId) async -> HomeManagableAction? {
        queuedRetries[entityId]
    }

    /// The fireplace as a test seeds and reads it: the states of `Fireplace.stateId`, oldest first.
    var fireplaceSwitches: [FireplaceSwitch] {
        get {
            storageItems.filter { $0.entityId == Fireplace.stateId }.compactMap { item in item.isDeviceOn.map { FireplaceSwitch(timestamp: item.timestamp, isOn: $0) } }
        }
        set {
            storageItems.removeAll { $0.entityId == Fireplace.stateId }
            storageItems += newValue.map { EntityStorageItem(entityId: Fireplace.stateId, timestamp: $0.timestamp, isDeviceOn: $0.isOn) }
        }
    }

    func listThermostats() async throws -> [Thermostat] { [] }

    func readThermostat(_ thermostat: Thermostat) async throws -> [EntityStorageItem] { [] }

    func getAllEntitiesLive() async throws -> [EntityStorageItem] {
        return storageItems
    }

    @discardableResult
    func addEntityHistory(_ item: EntityStorageItem) async -> Bool {
        let didChange: Bool
        if var knownItem = storageItems.last(where: { $0.entityId == item.entityId }) {
            knownItem.timestamp = item.timestamp
            didChange = knownItem != item
        } else {
            didChange = true
        }

        storageItems.append(item)
        return didChange
    }

    func getLocation() async -> Location {
        return Location(latitude: 0, longitude: 0)
    }

    private(set) var sentNotificationTitles: [String] = []

    /// The notifications `deliver` was asked to send.
    private(set) var sentNotifications: [(title: String, message: String, id: String, category: String?)] = []

    func deliver(_ delivery: Delivery) async {
        guard case let .push(title, message, id, category) = delivery else { return }
        sentNotificationTitles.append(title)
        sentNotifications.append((title, message, id, category))
        notificationDates[id] = Date()
    }

    /// When a notification with this id was last sent; a test sets it to place a push in the past.
    var notificationDates: [String: Date] = [:]

    func lastReports() async -> [String: Date] { [:] }

    /// Server-owned states reported by an automation under test, with the origin they were reported with.
    @discardableResult
    func report(_ entityId: EntityId, value: Value, origin: Origin) async throws -> Bool {
        guard entityId.isServerOwned else { throw ReportError.notServerOwned(entityId) }
        guard let item = EntityStorageItem(entityId: entityId, kind: entityId.characteristicType.valueKind, value: value, origin: origin) else {
            throw ReportError.valueDoesNotFit(entityId)
        }
        return await addEntityHistory(item)
    }

    func states(of kind: ValueKind) async -> [EntityStorageItem] {
        var latest: [EntityId: EntityStorageItem] = [:]
        for item in storageItems { latest[item.entityId] = item }
        return latest.values.filter { $0.entityId.characteristicType.valueKind == kind }
    }

    /// When each entity last reported, for a test that places a report in the past.
    var lastReports: [EntityId: Date] = [:]

    func lastReport(of entityId: EntityId) async -> Date? { lastReports[entityId] }

    func lastNotificationDate(id: String) async -> Date? {
        notificationDates[id]
    }

    func getEntityHistory(with entityId: EntityId, since: Date) async -> [EntityStorageItem] {
        storageItems.filter { $0.entityId == entityId && $0.timestamp >= since }.sorted { $0.timestamp > $1.timestamp }
    }

    func getFullEntityHistory(with entityId: EntityId, limit: Int) async -> [EntityStorageItem] {
        Array(storageItems.filter { $0.entityId == entityId }.sorted { $0.timestamp > $1.timestamp }.prefix(limit))
    }

    func performStorageUpkeep(_ step: StorageUpkeepStep, now: Date) async throws {
        upkeepSteps.append(step)
    }

    func homeKitHealth() async -> HomeKitHealth {
        health
    }
}

/// One state of the fireplace entity, for tests.
struct FireplaceSwitch: Equatable {
    let timestamp: Date
    let isOn: Bool
}
