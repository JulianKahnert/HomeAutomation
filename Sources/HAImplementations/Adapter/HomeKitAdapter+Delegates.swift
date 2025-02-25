//
//  HomeKitAdapter+Delegates.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 21.07.24.
//

#if canImport(HomeKit)
import HAModels
import HomeKit
import Logging

extension HomeKitAdapter {
    final class HomeKitHomeManager: NSObject, @unchecked Sendable {
        private let log = Logger(label: "HomeKitHomeManager")
        private var manager: HMHomeManager

        // push new homes to subscribers
        // the stream will return all homes that are available (unfiltered)
        private let homesPublisher = AsyncCurrentValuePublisher<[HMHome]>()

        // push new entity changes to subscribers
        // this stream will only publish entities values, e.g. which are included in the entityIds
        let entityStream: AsyncStream<EntityStorageItem>
        private let entityStreamContinuation: AsyncStream<EntityStorageItem>.Continuation

        init(entityStream: AsyncStream<EntityStorageItem>, entityStreamContinuation: AsyncStream<EntityStorageItem>.Continuation) {
            self.entityStream = entityStream
            self.entityStreamContinuation = entityStreamContinuation

            manager = HMHomeManager()
            super.init()
            manager.delegate = self

            // the connection to HomeKit seems to breake after x hours (e.g. no delegates will be called anymore), we try to reset the connection to avoid interruptions
            Task.detached(priority: .low) { [weak self] in
                for await _ in Timer.publish(every: .hours(6)) {
                    guard let self else { continue }

                    log.info("Resetting HMHomeManager to create a new HomeKit connection")
                    self.manager = HMHomeManager()
                    self.manager.delegate = self

                    await homesPublisher.send(self.manager.homes)
                }
            }
        }

        func getHomes() async -> [HMHome] {
            await homesPublisher.get()
        }

        func trigger(scene sceneName: String) async throws {
            let actionSet = try manager.homes.flatMap(\.actionSets).first(where: { $0.name == sceneName }).get(with: log)
            let home = try actionSet.home.get(with: log)

            try await home.executeActionSet(actionSet)
        }

        func updateEntities() async {
            log.debug("subscribeToCharacteristicNotifications")

            let homes = await homesPublisher.get()

            let allCharacteristics = Set(homes.flatMap(\.accessories)
                .flatMap(\.services)
                .flatMap(\.characteristics)
                .filter(\.isReadable)
                .filter(\.isNotifiable))

            // subscribe all new characteristics
            for characteristic in allCharacteristics.sorted() {
                guard let accessory = characteristic.service?.accessory else {
                    fatalError("Could not set delegate on accessory")
                }

                accessory.delegate = self

                let shouldSubscribe = characteristic.shouldSubscribe
                log.info("\(accessory.room?.name ?? "") @ \(characteristic.service?.name ?? ""): \(characteristic.localizedDescription) - \(characteristic.uniqueIdentifier.uuidString) - shouldSubscribe: \(shouldSubscribe)")

                do {
                    let isSubscribed = characteristic.isNotificationEnabled
                    if shouldSubscribe != isSubscribed {
                        try await characteristic.enableNotification(shouldSubscribe)
                    }
                } catch {
                    log.critical("Failed to enable notification on accessory \(accessory.name) - error \(error)")
                    assertionFailure()
                }
            }

            // send all items initially that are subscribed
            let items = await withTaskGroup(of: Optional<EntityStorageItem>.self) { group in
                for characteristic in allCharacteristics {
                    guard characteristic.shouldSubscribe else { continue }

                    group.addTask(priority: .medium) {
                        return await characteristic.getEntityStorageItem()
                    }
                }

                return await group.reduce(into: [EntityStorageItem]()) { partialResult, item in
                    partialResult.append(item)
                }
            }

            for item in items.compactMap(\.self) {
                self.entityStreamContinuation.yield(item)
            }
        }

        private func update(homes: [HMHome]) {
            log.info("update accessories")
            for home in homes {
                home.delegate = self
            }

            Task {
                await homesPublisher.send(homes)
                await updateEntities()
            }
        }

        private func checkAuthorization() {
            if manager.authorizationStatus != .authorized {
                log.critical("homeManager.authorizationStatus - not authorized")
            }
        }
    }
}

extension HomeKitAdapter.HomeKitHomeManager: HMHomeManagerDelegate {
    func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        log.info("homeManager.homeManagerDidUpdateHomes")
        update(homes: manager.homes)
    }
    func homeManager(_ manager: HMHomeManager, didUpdate status: HMHomeManagerAuthorizationStatus) {
        log.info("homeManager.didUpdate \(status.rawValue)")
        checkAuthorization()
        update(homes: manager.homes)
    }
}

extension HomeKitAdapter.HomeKitHomeManager: HMHomeDelegate {
    func home(_ home: HMHome, didAdd accessory: HMAccessory) {
        log.info("home:didAdd accessory \(accessory.name)")
        update(homes: manager.homes)
    }

    func home(_ home: HMHome, didRemove accessory: HMAccessory) {
        log.info("home:didRemove accessory \(accessory.name)")
        update(homes: manager.homes)
    }

    func home(_ home: HMHome, didEncounterError error: any Error, for accessory: HMAccessory) {
        log.info("home:didEncounterError accessory \(accessory.name)")
        update(homes: manager.homes)
    }

    func home(_ home: HMHome, didUnblockAccessory accessory: HMAccessory) {
        log.info("home:didUnblockAccessory accessory \(accessory.name)")
        update(homes: manager.homes)
    }
}

extension HomeKitAdapter.HomeKitHomeManager: HMAccessoryDelegate {
    func accessoryDidUpdateName(_ accessory: HMAccessory) {
        log.info("accessory:accessoryDidUpdateName(HMAccessory) \(accessory.name)")
        update(homes: manager.homes)

    }
    func accessoryDidUpdateReachability(_ accessory: HMAccessory) {
        log.info("accessory:accessoryDidUpdateReachability(HMAccessory) \(accessory.name)")
        update(homes: manager.homes)

    }
    func accessoryDidUpdateServices(_ accessory: HMAccessory) {
        log.info("accessory:accessoryDidUpdateServices(HMAccessory) \(accessory.name)")
        update(homes: manager.homes)
    }
    func accessory(_ accessory: HMAccessory, didUpdateNameFor: HMService) {
        log.info("accessory:accessory(HMAccessory, didUpdateNameFor: HMService) \(accessory.name)")
        update(homes: manager.homes)
    }
    func accessory(_ accessory: HMAccessory, service: HMService, didUpdateValueFor characteristic: HMCharacteristic) {
        Task {
            let item = await characteristic.getEntityStorageItem()
            log.info("home:didUpdateValueFor accessory [\(accessory.room?.name ?? "") @ \(characteristic.service?.name ?? "")] changed characteristic [\(characteristic.localizedDescription)]")
            guard let item else { return }
            self.entityStreamContinuation.yield(item)
        }
    }
    func accessory(_ accessory: HMAccessory, didUpdateAssociatedServiceTypeFor: HMService) {
        log.info("accessory:accessory(HMAccessory, didUpdateAssociatedServiceTypeFor: HMService) \(accessory.name)")
        update(homes: manager.homes)
    }
    func accessory(_ accessory: HMAccessory, didAdd: HMAccessoryProfile) {
        log.info("accessory:accessory(HMAccessory, didAdd: HMAccessoryProfile) \(accessory.name)")
        update(homes: manager.homes)
    }
    func accessory(_ accessory: HMAccessory, didRemove: HMAccessoryProfile) {
        log.info("accessory:accessory(HMAccessory, didRemove: HMAccessoryProfile) \(accessory.name)")
        update(homes: manager.homes)
    }
    func accessory(_ accessory: HMAccessory, didUpdateFirmwareVersion: String) {
        log.info("accessory:accessory(HMAccessory, didUpdateFirmwareVersion: String) \(accessory.name)")
        update(homes: manager.homes)
    }
}
#endif
