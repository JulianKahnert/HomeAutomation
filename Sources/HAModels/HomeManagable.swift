//
//  HomeManagable.swift
//  
//
//  Created by Julian Kahnert on 03.07.24.
//

import Foundation

@globalActor
public actor HomeManagerActor: GlobalActor {
    public static let shared = HomeManagerActor()
}

@HomeManagerActor
public protocol HomeManagable: Sendable {
    func getCurrentEntity(with entityId: EntityId) async throws -> EntityStorageItem
    func getPreviousEntity(with entityId: EntityId) async throws -> EntityStorageItem?
    func getAllEntitiesLive() async throws -> [EntityStorageItem]
    func addEntityHistory(_ item: EntityStorageItem) async
    func findEntity(_ entity: EntityId) async throws

    func perform(_ action: HomeManagableAction) async
    func trigger(scene sceneName: String) async
    func maintenance() async throws
    func deleteStorageEntries(olderThan date: Date) async throws
    func getLocation() async -> Location
    func sendNotification(title: String, message: String) async
    func getWindowStates() async -> [WindowOpenState]
    func getActionLog(limit: Int?) async -> [ActionLogItem]
    func clearActionLog() async
}

public enum HomeManagableAction: CustomStringConvertible, Sendable, Codable, Equatable {
    public enum SceneEntityAction: Sendable, Codable, Equatable {
        case lockDoor
        case on
        case off
    }
    case turnOn(EntityId)
    case turnOff(EntityId)
    case setBrightness(EntityId, Float)
    case setColorTemperature(EntityId, Float)
    case setRGB(EntityId, rgb: RGB)
    case lockDoor(EntityId)
    case addEntityToScene(EntityId, sceneName: String, targetValue: SceneEntityAction)
    case setHeating(EntityId, active: Bool)
    case setValve(EntityId, active: Bool)

    public var description: String {
        switch self {
        case .turnOn:
            return "turnOn"
        case .turnOff:
            return "turnOff"
        case .setBrightness(_, let float):
            return "setBrightness(\(float))"
        case .setColorTemperature(_, let float):
            return "setColorTemperature(\(float))"
        case .setRGB(_, rgb: let rgb):
            return "setRGB(red: \(rgb.red), green: \(rgb.green), blue: \(rgb.blue)"
        case .lockDoor:
            return "lockDoor"
        case .addEntityToScene(_, let sceneName, let value):
            return "addEntityToScene(sceneName: \(sceneName) \(value))"
        case .setHeating(_, let active):
            return "setHeating(active: \(active))"
        case .setValve(_, let active):
            return "setValve(active: \(active))"
        }
    }

    public var entityId: EntityId {
        switch self {
        case .turnOn(let entityId):
            return entityId
        case .turnOff(let entityId):
            return entityId
        case .setBrightness(let entityId, _):
            return entityId
        case .setColorTemperature(let entityId, _):
            return entityId
        case .setRGB(let entityId, _):
            return entityId
        case .lockDoor(let entityId):
            return entityId
        case .addEntityToScene(let entityId, _, _):
            return entityId
        case .setHeating(let entityId, _):
            return entityId
        case .setValve(let entityId, _):
            return entityId
        }
    }

    public var actionName: String {
        switch self {
        case .turnOn:
            return "turnOn"
        case .turnOff:
            return "turnOff"
        case .setBrightness:
            return "setBrightness"
        case .setColorTemperature:
            return "setColorTemperature"
        case .setRGB:
            return "setRGB"
        case .lockDoor:
            return "lockDoor"
        case .addEntityToScene:
            return "addEntityToScene"
        case .setHeating:
            return "setHeating"
        case .setValve:
            return "setValve"
        }
    }
}
