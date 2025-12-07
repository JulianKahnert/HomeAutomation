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
    private let log = Logger(label: "MockHomeAdapter")
    private var traceMap: [String: Int] = [:]

    init() {
        let (entityStream, entityStreamContinuation) = AsyncStream.makeStream(of: EntityStorageItem.self, bufferingPolicy: .unbounded)
        self.entityStream = entityStream
        self.entityStreamContinuation = entityStreamContinuation
    }

    func perform(_ action: HomeManagableAction) async {

        let item = storageItems.first(where: { $0.entityId == action.entityId })

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
        case .setHeating:
            break
        case .setValve:
            break
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
        }

        traceMap["action.\(actionString)", default: 0] += 1
    }

    func setUsedEntityIds(_ entityIds: Set<HAModels.EntityId>) async {
        traceMap["setUsedEntityIds.count:\(entityIds.count)", default: 0] += 1
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

    func getAllEntitiesLive() async throws -> [EntityStorageItem] {
        return storageItems
    }

    func addEntityHistory(_ item: EntityStorageItem) async {
        storageItems.append(item)
    }

    func maintenance() async throws {
    }

    func deleteStorageEntries(olderThan date: Date) async throws {
    }

    func getLocation() async -> Location {
        return Location(latitude: 0, longitude: 0)
    }

    func sendNotification(title: String, message: String) async {
    }

    func getWindowStates() async -> [WindowOpenState] {
        return []
    }

    func getActionLog(limit: Int?) async -> [ActionLogItem] {
        return []
    }

    func clearActionLog() async {
    }
}
