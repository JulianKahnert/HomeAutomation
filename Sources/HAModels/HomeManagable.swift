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

public protocol EntityValidator {
    func findEntity(_ entity: EntityId) async throws
}

@HomeManagerActor
public protocol HomeManagable: EntityValidator, Sendable {
    func getCurrentEntity(with entityId: EntityId) async throws -> EntityStorageItem
    /// When each reporting source (an origin: `homekit`, `server` or a job name) last reported, a replay included.
    /// Memory only, so a source is missing after a restart until its first report.
    func lastReports() async -> [String: Date]
    /// When the entity last reported, a replay included; `nil` while unknown (after a restart until its first report).
    func lastReport(of entityId: EntityId) async -> Date?
    func getPreviousEntity(with entityId: EntityId) async throws -> EntityStorageItem?
    /// The last state of the entity the database holds, past the in-memory cache. After a restart the
    /// adapter's resync refreshes the cache with a new timestamp; only the database still knows since
    /// when the state really holds. `nil` when the database has none.
    func getStoredEntity(with entityId: EntityId) async -> EntityStorageItem?
    /// The stored states of the entity since `since`, newest first; empty when the database has none.
    func getEntityHistory(with entityId: EntityId, since: Date) async -> [EntityStorageItem]
    /// When a notification with this id was last sent by this server process; `nil` if none was since the start.
    func lastNotificationDate(id: String) async -> Date?
    /// The newest write that reached `radiator` (matched by room and name, whatever the characteristic),
    /// `nil` when there is none or the server does not record them.
    func lastHeatingWrite(of radiator: EntityId) async -> HeatingWrite?
    /// Records a write of the plan history that sends nothing (`HeatingWrite.sentToDevice` is `false`).
    func record(_ write: HeatingWrite) async
    /// The command queued to be sent again for `entityId` after it failed, `nil` when none waits.
    func queuedRetry(of entityId: EntityId) async -> HomeManagableAction?
    /// The newest switch of the fireplace (glossary: fireplace mode), `nil` when it was never switched.
    func lastFireplaceSwitch() async -> FireplaceSwitch?
    /// Switches the fireplace and tells the automations (`HomeEvent.fireplaceChanged`). Returns the new switch,
    /// `nil` when the fireplace already had that state.
    func switchFireplace(isOn: Bool, at date: Date) async -> FireplaceSwitch?
    func getAllEntitiesLive() async throws -> [EntityStorageItem]
    /// - Returns: Whether the item carries new information, i.e. differs in value — not just in
    ///   timestamp — from the last known state of that entity.
    @discardableResult
    func addEntityHistory(_ item: EntityStorageItem) async -> Bool

    func perform(_ action: HomeManagableAction) async
    func trigger(scene sceneName: String) async
    func getLocation() async -> Location
    /// Hands a push or Live Activity update over to the notification adapter. Deliveries leave in the order
    /// they were handed over, also when one send is slow; a failed send is logged, not thrown.
    func deliver(_ delivery: Delivery) async
    /// Marks an offenes Fenster überschritten once its Fensterschließzeit has passed; the Live Activity alerts once.
    func markWindowOverdue(entityId: EntityId) async
    /// The window Live Activity's content state, as the server last built it.
    func getWindowContentState() async -> WindowContentState
    func setWindowOpenState(entityId: EntityId, to state: WindowOpenState?) async
    func getActionLog(limit: Int?, runId: UUID?) async -> [ActionLogItem]
    func clearActionLog() async
    /// Whether HomeKit works end to end; shared by `/health` and the `HealthCheck` automation.
    func homeKitHealth() async -> HomeKitHealth
    /// Runs one step of the database upkeep (cleanup, rollup). A no-op where the host has no database upkeep.
    func performStorageUpkeep(_ step: StorageUpkeepStep, now: Date) async throws
}

public enum HomeManagableAction: CustomStringConvertible, Sendable, Codable, Equatable {
    public enum SceneEntityAction: Sendable, Codable, Equatable {
        case lockDoor
        // swiftlint:disable:next identifier_name - "on" is the Codable key in stored config JSON and used by the config repo
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
    /// Writes the heating threshold of a radiator (`.targetTemperature`); rounded to 0.5 °C, the step of the Eve Thermo.
    case setTargetTemperature(EntityId, celsius: Double)

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
        case .setTargetTemperature(_, let celsius):
            return "setTargetTemperature(celsius: \(celsius))"
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
        case .setTargetTemperature(let entityId, _):
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
        case .setTargetTemperature:
            return "setTargetTemperature"
        }
    }
}
