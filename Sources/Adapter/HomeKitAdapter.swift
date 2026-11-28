//
//  HomeKitAdapter.swift
//  
//
//  Created by Julian Kahnert on 03.07.24.
//

import HAModels

public protocol HomeKitAdapterable: Sendable {
    func getAllEntitiesLive() async -> [EntityStorageItem]

    func perform(_ action: HomeManagableAction) async throws
    func trigger(scene sceneName: String) async throws

    func listThermostats() async throws -> [Thermostat]
    func readThermostat(_ thermostat: Thermostat) async throws -> [EntityStorageItem]
}

#if canImport(HomeKit)
import Foundation
import HAModels
import HomeKit
import Logging
import Shared

public final class HomeKitAdapter: HomeKitAdapterable {
    private let log = Logger(label: "HomeKitAdapter")
    private let homeKitHomeManager: HomeKitHomeManager

    public init(entityStream: AsyncStream<EntityStorageItem>, entityStreamContinuation: AsyncStream<EntityStorageItem>.Continuation) {
        self.homeKitHomeManager = HomeKitHomeManager(entityStream: entityStream, entityStreamContinuation: entityStreamContinuation)
    }

    /// Re-yields the full current entity state onto the entity stream.
    ///
    /// Used after a (re)connect to the server so it never misses state changes
    /// that happened while the link was down. Reuses the existing full-refresh
    /// path, which also re-checks characteristic subscriptions — undelayed, but
    /// serialized against a refresh that is already running.
    public func pushFullState() async {
        log.info("pushFullState() — re-yielding full entity state after (re)connect")
        await homeKitHomeManager.updateEntitiesNow()
    }

    /// Everything HomeKit knows, one row per characteristic, see `HomeKitInventoryItem`.
    public func inventory() async -> [HomeKitInventoryItem] {
        await homeKitHomeManager.inventory()
    }

    /// One element per debounced request for a fresh inventory (the homes changed).
    public var inventoryRequests: AsyncStream<Void> { homeKitHomeManager.inventoryRequests }

    public func getAllEntitiesLive() async -> [EntityStorageItem] {
        let start = ContinuousClock.now
        let characteristics = await getCharacteristics()
        log.info("getAllEntitiesLive() — querying \(characteristics.count) characteristics")

        let items = await withTaskGroup(of: Optional<EntityStorageItem>.self) { group in
            for characteristic in characteristics {
                group.addTask(priority: .low) {
                    return await characteristic.getEntityStorageItem()
                }
            }

            return await group.reduce(into: [EntityStorageItem]()) { partialResult, item in
                partialResult.append(item)
            }
        }

        let result = items.compactMap(\.self)
        let duration = start.duration(to: .now)
        log.info("getAllEntitiesLive() — returned \(result.count) entities from \(characteristics.count) characteristics in \(duration)")
        return result
    }

    public func perform(_ action: HomeManagableAction) async throws {
        do {
            try await performAction(action)
        } catch {
            await homeKitHomeManager.handleCommandFailure(error)
            throw error
        }
    }

    private func performAction(_ action: HomeManagableAction) async throws {
        let characteristics = await getCharacteristics()
        let filteredCharacteristics = characteristics.filter({ $0.entityId == action.entityId })
        guard filteredCharacteristics.count == 1,
              let characteristic = filteredCharacteristics.first else {
            // Must throw, not return: a silent success would let the server mark the command as
            // executed and dedup every retry of it. Reachable whenever the homes list is
            // transiently empty (e.g. during the 6h HMHomeManager reset).
            log.error("Failed to get characteristic for \(action.entityId)")
            throw OptionalError.notFound
        }
        log.info("Perform action [\(action)] on [\(characteristic)]")

        let newValue: NSNumber
        switch action {
        case .turnOn:
            newValue = NSNumber(value: true)

        case .turnOff:
            newValue = NSNumber(value: false)

        case .setBrightness(_, let value):
            assert((0.0...1.0).contains(value), "Value (\(value) out of bounds")
            guard let minimumValue = characteristic.metadata?.minimumValue,
                  let maximumValue = characteristic.metadata?.maximumValue else {
                log.error("Failed to get brightness bounds of \(action.entityId)")
                throw OptionalError.notFound
            }
            let adjustedValue = Float(truncating: minimumValue) + value * (Float(truncating: maximumValue) - Float(truncating: minimumValue))
            newValue = NSNumber(value: Int64(adjustedValue))

        case .setColorTemperature(_, let value):
            assert((0.0...1.0).contains(value), "Value (\(value) out of bounds")
            guard let minimumValue = characteristic.metadata?.minimumValue,
                  let maximumValue = characteristic.metadata?.maximumValue else {
                log.error("Failed to get color temperature bounds of \(action.entityId)")
                throw OptionalError.notFound
            }

            let adjustedValue = Float(truncating: minimumValue) + (1 - value) * (Float(truncating: maximumValue) - Float(truncating: minimumValue))
            newValue = NSNumber(value: Int64(adjustedValue))

        case .setRGB(_, rgb: let rgb):
            let hsv = hsv(from: rgb)
            newValue = NSNumber(value: hsv.h)

            // color sometimes only changes when saturation was also changed
            let saturationCharacteristic = characteristic.service?.characteristics.first(where: { $0.characteristicType == HMCharacteristicTypeSaturation })
            try await saturationCharacteristic?.writeValue(NSNumber(value: Int(hsv.s * 100)))

        case .lockDoor:
            newValue = NSNumber(value: HMCharacteristicValueLockMechanismState.secured.rawValue)
        case .addEntityToScene(_, sceneName: let sceneName, let action):
            guard let home = characteristic.service?.accessory?.home else {
                log.error("Failed to get home for characteristic")
                throw OptionalError.notFound
            }

            // create scene if not exists
            if !home.actionSets.contains(where: { $0.name == sceneName }) {
                try await home.addActionSet(named: sceneName)
            }
            guard let scene = home.actionSets.first(where: { $0.name == sceneName }) else {
                log.error("Could not find scene named \(sceneName)")
                throw OptionalError.notFound
            }

            // add action if not exists
            let action = HMCharacteristicWriteAction(characteristic: characteristic, targetValue: action.value)
            if scene.actions.contains(action) {
                // action already exists - nothing to do
            } else if let action = scene.actions.first(where: { $0.characteristic == characteristic }) {
                // action exists but with a different target
                try await scene.removeAction(action)
                try await scene.addAction(action)
            } else {
                // no action exists - create a new one
                try await scene.addAction(action)
            }
            return
        case .setHeating(_, let active):
            newValue = NSNumber(value: active)
        case .setValve(_, let active):
            newValue = NSNumber(value: active)
        case .setTargetTemperature(_, let celsius):
            var clamped = celsius
            if let minimumValue = characteristic.metadata?.minimumValue?.doubleValue {
                clamped = max(clamped, minimumValue)
            }
            if let maximumValue = characteristic.metadata?.maximumValue?.doubleValue {
                clamped = min(clamped, maximumValue)
            }
            newValue = NSNumber(value: clamped)
        }

        do {
            try await characteristic.writeValue(newValue)
        } catch {
            try await characteristic.readValue()

            // rethrow the error, if "performAction" did not set the correct value
            guard let value = characteristic.value as? NSNumber,
                  value == newValue else {
                log.error("Failed to set the correct value")
                throw error
            }

            log.warning("An error was thrown, but the value is correct\n\(error)")
        }
    }

    public func trigger(scene sceneName: String) async throws {
        log.info("triggering scene: \(sceneName)")
        do {
            try await homeKitHomeManager.trigger(scene: sceneName)
        } catch {
            log.error("Failed to trigger scene '\(sceneName)': \(error)")
            await homeKitHomeManager.handleCommandFailure(error)
            throw error
        }
    }

    public func listThermostats() async throws -> [Thermostat] {
        try await homeKitHomeManager.listThermostats()
    }

    public func readThermostat(_ thermostat: Thermostat) async throws -> [EntityStorageItem] {
        try await homeKitHomeManager.readThermostat(thermostat)
    }

    /// Attention: This call might take a while so be carefull with it
    private func getCharacteristics() async -> [HMCharacteristic] {
        let homes = await homeKitHomeManager.getHomes()
        return homes.flatMap(\.accessories)
            .flatMap(\.services)
            .flatMap(\.characteristics)
            .filter(\.isReadable)
            .sorted()
    }
}

extension HomeManagableAction.SceneEntityAction {
    var value: NSNumber {
        switch self {
        case .on:
            return NSNumber(value: true)
        case .off:
            return NSNumber(value: false)
        case .lockDoor:
            return NSNumber(value: HMCharacteristicValueLockMechanismState.secured.rawValue)
        }
    }
}
#endif
