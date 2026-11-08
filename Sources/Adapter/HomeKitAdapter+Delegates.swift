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
import Shared
#if canImport(UIKit)
import UIKit
#endif

extension HomeKitAdapter {
    final class HomeKitHomeManager: NSObject, @unchecked Sendable {
        private let log = Logger(label: "HomeKitHomeManager")
        private var manager: HMHomeManager
        /// The manager replaced by the last reset, kept alive until its successor delivered homes so
        /// the homes still published keep working in between.
        private var retiredManager: HMHomeManager?

        // push new homes to subscribers
        // the stream will return all homes that are available (unfiltered)
        private let homesPublisher = AsyncCurrentValuePublisher<[HMHome]>()

        // push new entity changes to subscribers
        // this stream will only publish entities values, e.g. which are included in the entityIds
        let entityStream: AsyncStream<EntityStorageItem>
        private let entityStreamContinuation: AsyncStream<EntityStorageItem>.Continuation

        /// The only path that runs `updateEntities()`. A single reachability flap makes HomeKit fire
        /// a burst of delegate callbacks, and each one would otherwise start a full rescan that
        /// re-yields every entity; the debouncer collapses the burst and keeps rescans from
        /// overlapping. Assigned before the delegates so no callback can find it missing.
        private var entityUpdateDebouncer: AsyncDebouncer!

        /// Reasons for the next `updateEntities()` to re-register every notification, see
        /// `NotificationResubscription`.
        private let resubscribeRequests = ResubscribeRequests()

        init(entityStream: AsyncStream<EntityStorageItem>, entityStreamContinuation: AsyncStream<EntityStorageItem>.Continuation) {
            self.entityStream = entityStream
            self.entityStreamContinuation = entityStreamContinuation

            manager = HMHomeManager()
            super.init()
            entityUpdateDebouncer = AsyncDebouncer(delay: .seconds(5)) { [weak self] in
                await self?.updateEntities()
            }
            manager.delegate = self

            startManagerResets()
        }

        func getHomes() async -> [HMHome] {
            await homesPublisher.get()
        }

        func trigger(scene sceneName: String) async throws {
            // The published homes, not `manager.homes`: `resetManager()` swaps `manager` on the main
            // actor, and the new manager has no homes until its first `homeManagerDidUpdateHomes`.
            let homes = await homesPublisher.get()
            let actionSet = try homes.flatMap(\.actionSets).first(where: { $0.name == sceneName }).get(with: log)
            let home = try actionSet.home.get(with: log)

            log.info("Executing action set: \(actionSet.name) [\(home.description)]")
            do {
                try await home.executeActionSet(actionSet)
            } catch {
                log.error("Failed to execute action set '\(actionSet.name)': \(error)")
                throw error
            }
        }

        /// Request a full entity refresh after the debounce delay.
        func scheduleEntityUpdate() async {
            await entityUpdateDebouncer.schedule()
        }

        /// A command refused with Code=80 while the app is not in the background means `homed`
        /// dropped the registrations, so force a resubscribe.
        func handleCommandFailure(_ error: any Error) async {
            guard NotificationResubscription.isBackgroundAccessDenied(error) else { return }
            #if canImport(UIKit)
            let isBackground = await MainActor.run { UIApplication.shared.applicationState == .background }
            guard !isBackground else { return }
            #endif
            // While `homed` still refuses, every resubscribe fails too; the server's retries must
            // not turn into one full resubscribe of every characteristic per debounce window.
            guard await resubscribeRequests.request(reason: "backgroundAccessDenied",
                                                    notWithin: .seconds(60),
                                                    now: .now) else { return }
            await scheduleEntityUpdate()
        }

        /// Request a full entity refresh without waiting for the debounce delay — a reconnect resync
        /// must not be deferred or coalesced away — but still serialized against a running refresh.
        func updateEntitiesNow() async {
            await entityUpdateDebouncer.runNow()
        }

        private func updateEntities() async {
            let start = ContinuousClock.now
            let homes = await homesPublisher.get()

            let allCharacteristics = Set(homes.flatMap(\.accessories)
                .flatMap(\.services)
                .flatMap(\.characteristics)
                .filter(\.isReadable)
                .filter(\.isNotifiable))

            log.info("updateEntities() — processing \(allCharacteristics.count) characteristics")

            let resubscribeReasons = await resubscribeRequests.take()

            // subscribe all new characteristics
            var subscriptionChanges = 0
            var subscriptionErrors = 0
            for characteristic in allCharacteristics.sorted() {
                guard let accessory = characteristic.service?.accessory else {
                    // The back-reference can be transiently nil while HomeKit re-builds its object
                    // graph; the next rescan picks the characteristic up again.
                    log.error("Could not set delegate on accessory of characteristic \(characteristic.uniqueIdentifier.uuidString)")
                    continue
                }

                accessory.delegate = self

                let shouldSubscribe = characteristic.shouldSubscribe
                log.info("\(accessory.room?.name ?? "") @ \(characteristic.service?.name ?? ""): \(characteristic.localizedDescription) - \(characteristic.uniqueIdentifier.uuidString) - shouldSubscribe: \(shouldSubscribe)")

                do {
                    let requests = NotificationResubscription.notificationRequests(
                        shouldSubscribe: shouldSubscribe,
                        isNotificationEnabled: characteristic.isNotificationEnabled,
                        force: resubscribeReasons != nil)
                    for enable in requests {
                        try await characteristic.enableNotification(enable)
                    }
                    if !requests.isEmpty {
                        subscriptionChanges += 1
                    }
                } catch {
                    // This path runs on every reconnect resync, so it must never
                    // assert/crash — transient HomeKit errors are expected here.
                    subscriptionErrors += 1
                    log.error("Failed to enable notification on accessory \(accessory.name) - error \(error)")
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

            if let resubscribeReasons {
                log.info("Resubscribed characteristic notifications", metadata: [
                    "reasons": "\(resubscribeReasons.joined(separator: ","))",
                    "characteristics": "\(allCharacteristics.filter(\.shouldSubscribe).count)",
                    "failures": "\(subscriptionErrors)"
                ])
            }

            let duration = start.duration(to: .now)
            log.info("updateEntities() — completed in \(duration) (changes: \(subscriptionChanges), errors: \(subscriptionErrors))")
        }

        private func update(homes: [HMHome], resubscribeReason: String? = nil, releasesRetiredManager: Bool = false) {
            log.info("update(homes:) — starting with \(homes.count) homes")
            for home in homes {
                home.delegate = self
            }

            // `homesPublisher` stays immediate: `getAllEntitiesLive()` and `perform(_:)` read the
            // homes through it, and its first value unblocks callers that are already waiting.
            Task {
                await homesPublisher.send(homes)
                if releasesRetiredManager {
                    // Only now nobody reads the old manager's homes any more. On the main actor
                    // like `resetManager()`, which sets it.
                    await MainActor.run { self.retiredManager = nil }
                }
                if let resubscribeReason {
                    await resubscribeRequests.request(reason: resubscribeReason)
                }
                await scheduleEntityUpdate()
            }
        }

        /// HomeKit delegate callbacks seem to stop after some hours, so a fresh `HMHomeManager`
        /// replaces the old one every 6 h. Its `homeManagerDidUpdateHomes` forces a resubscribe.
        private func startManagerResets() {
            Task { @MainActor [weak self] in
                while true {
                    do {
                        try await Task.sleep(for: .hours(6))
                    } catch {
                        return
                    }
                    guard let self else { return }
                    resetManager()
                }
            }
        }

        @MainActor
        private func resetManager() {
            log.info("Resetting HMHomeManager to create a new HomeKit connection")
            manager.delegate = nil
            retiredManager = manager
            manager = HMHomeManager()
            manager.delegate = self
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
        // also the first callback of the manager created by a reset, whose registrations start empty
        update(homes: manager.homes, resubscribeReason: "homeManagerDidUpdateHomes", releasesRetiredManager: true)
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
        log.error("home:didEncounterError accessory '\(accessory.name)': \(error)")
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
