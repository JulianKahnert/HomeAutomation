//
//  HomeKitAdapter.swift
//  
//
//  Created by Julian Kahnert on 03.07.24.
//

import HAModels

public protocol HomeKitAdapterable: EntityValidator, Sendable {
//    func getEntityStream() async -> AsyncStream<EntityStorageItem>
    func getAllEntitiesLive() async -> [EntityStorageItem]
    func findEntity(_ entity: EntityId) async throws

    func perform(_ action: HomeManagableAction) async throws
    func trigger(scene sceneName: String) async throws
}

#if canImport(HomeKit)
import DistributedCluster
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

//        Task.detached {
//            try! await Task.sleep(for: .seconds(1))
//            
//            print("debugging start")
//            let entity = EntityId(placeId: "Garten", name: "Garage Front R", characteristicsName: nil, characteristic: .brightness)
////            try! await self.perform(.turnOn(entity))
//            try! await self.perform(.setBrightness(entity, 0.1))
//            print("debugging end")
//        }
    }

    public  func getAllEntitiesLive() async -> [EntityStorageItem] {
        let characteristics = await getCharacteristics()
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

        return items.compactMap(\.self)
    }

    public func findEntity(_ entity: EntityId) async throws {
        let characteristics = await getCharacteristics()
        let filteredCharacteristics = characteristics.filter({ $0.entityId == entity })
        guard filteredCharacteristics.count == 1 else {
            log.debug("Found: \(filteredCharacteristics)")
            log.critical("Validation: Could not find entity \(entity)")
            assertionFailure()
            throw OptionalError.notFound
        }
    }

    public func perform(_ action: HomeManagableAction) async throws {
        let characteristics = await getCharacteristics()
        let filteredCharacteristics = characteristics.filter({ $0.entityId == action.entityId })
        guard filteredCharacteristics.count == 1,
              let characteristic = filteredCharacteristics.first else {
            log.critical("Failed to get characteristic")
            assertionFailure()
            return
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
                assertionFailure()
                return
            }
            let adjustedValue = Float(truncating: minimumValue) + value * (Float(truncating: maximumValue) - Float(truncating: minimumValue))
            newValue = NSNumber(value: Int64(adjustedValue))

        case .setColorTemperature(_, let value):
            assert((0.0...1.0).contains(value), "Value (\(value) out of bounds")
            guard let minimumValue = characteristic.metadata?.minimumValue,
                  let maximumValue = characteristic.metadata?.maximumValue else {
                assertionFailure()
                return
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
                log.critical("Failed to get home for characteristic")
                assertionFailure()
                return
            }

            // create scene if not exists
            if !home.actionSets.contains(where: { $0.name == sceneName }) {
                try await home.addActionSet(named: sceneName)
            }
            guard let scene = home.actionSets.first(where: { $0.name == sceneName }) else {
                log.critical("Could not find scene named \(sceneName)")
                assertionFailure()
                return
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
        try await homeKitHomeManager.trigger(scene: sceneName)
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

    // MARK: - Debug Helpers

    #if DEBUG
    /// Prints all characteristics for a specific accessory identified by entityId
    ///
    /// This method helps developers understand what properties are available on a device
    /// during local development. Use this when adding support for new HomeKit devices.
    ///
    /// - Parameter entityId: The EntityId of any characteristic belonging to the accessory
    public func debugPrintAccessory(placeId: String, name: String) async {
        let homes = await homeKitHomeManager.getHomes()
        let accessories = homes.flatMap(\.accessories)

        guard let accessory = accessories.first(where: { $0.room?.name == placeId && $0.name == name }) else {
            log.info("❌ Accessory for entityId '\(name) [\(placeId)]' not found")
            return
        }

        var output = "\n=== Debug Info for Accessory with EntityId '\(name) [\(placeId)]' ===\n"
        output += "Accessory Name: \(accessory.name)\n"
        output += "Unique Identifier: \(accessory.uniqueIdentifier)\n"
        output += "Services: \(accessory.services.count)"

        for service in accessory.services {
            output += "\n\n📦 Service: \(service.localizedDescription) (\(service.serviceType))"

            for char in service.characteristics {
                output += "\n  └─ \(char.localizedDescription)"
                output += "\n     Value: \(char.value ?? "nil")"
                output += "\n     Properties: \(char.properties)"

                if let metadata = char.metadata {
                    if let min = metadata.minimumValue { output += "\n     Min: \(min)" }
                    if let max = metadata.maximumValue { output += "\n     Max: \(max)" }
                    if let step = metadata.stepValue { output += "\n     Step: \(step)" }
                    if let format = metadata.format { output += "\n     Format: \(format)" }
                }

                // Show what EntityId would look like for this characteristic
                if let entityCharType = char.entityCharacteristicType,
                   let charEntityId = char.entityId {
                    output += "\n     ✅ EntityId: \(charEntityId)"
                    output += "\n     CharacteristicType: .\(entityCharType)"
                }
            }
        }
        output += "\n\n=== End Debug Info ===\n"
        log.info("\(output)")
    }

    /// Prints all accessories and their entityIds for basic characteristics
    ///
    /// Use this method to discover available accessories and their EntityIds.
    /// This is useful when you want to inspect a specific device using debugPrintAccessory.
    public func debugPrintAllAccessories() async {
        let homes = await homeKitHomeManager.getHomes()
        log.info("=== All HomeKit Accessories ===")

        for home in homes {
            for accessory in home.accessories.sorted(by: { ($0.room?.name ?? "") < ($1.room?.name ?? "") }) {
                let roomName = accessory.room?.name ?? "No Room"
                var output = "🏠 Home: \(home.name)\n"
                output += "📱 \(accessory.name) (Room: \(roomName))\n"
                output += "Accessory ID: \(accessory.uniqueIdentifier)"

                // Print entityIds for common characteristics
                for service in accessory.services {
                    for char in service.characteristics.filter({ $0.isReadable }) {
                        if let entityCharType = char.entityCharacteristicType,
                           let entityId = char.entityId {
                            output += "\n- [\(entityCharType)] \(entityId)"
                        }
                    }
                }

                log.info("\(output)")
            }
        }

        log.info("=== End All Accessories ===")
    }
    #endif
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
