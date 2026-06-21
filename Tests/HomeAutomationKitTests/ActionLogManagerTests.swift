//
//  ActionLogManagerTests.swift
//  HomeAutomationKit
//
//  Created by Claude Code on 21.06.26.
//

import Foundation
@testable import HAApplicationLayer
import HAModels
import Testing

struct ActionLogManagerTests {

    private let switchId = EntityId(placeId: "room", name: "light", characteristicsName: nil, characteristic: .switcher)
    private let brightnessId = EntityId(placeId: "room", name: "light", characteristicsName: nil, characteristic: .brightness)

    @Test("Confirming echo does not invalidate — dedup is preserved (no command storm)")
    func echoPreservesDedup() async {
        let manager = ActionLogManager()
        let action = HomeManagableAction.turnOn(switchId)

        #expect(await manager.log(action: action) == false) // first call: miss → cached

        let echo = EntityStorageItem(entityId: switchId, isDeviceOn: true)
        let invalidated = await manager.invalidateContradictedCommands(for: echo)
        #expect(invalidated.isEmpty)

        #expect(await manager.log(action: action) == true) // still deduped
    }

    @Test("Contradicting state invalidates — command may be re-issued")
    func driftInvalidates() async {
        let manager = ActionLogManager()
        let action = HomeManagableAction.turnOn(switchId)

        #expect(await manager.log(action: action) == false)

        let drift = EntityStorageItem(entityId: switchId, isDeviceOn: false)
        let invalidated = await manager.invalidateContradictedCommands(for: drift)
        #expect(invalidated == [action])

        #expect(await manager.log(action: action) == false) // re-issue allowed (cache miss)
    }

    @Test("setBrightness echo preserves dedup, drift invalidates")
    func brightnessDrift() async {
        let manager = ActionLogManager()
        let action = HomeManagableAction.setBrightness(brightnessId, 0.5)

        #expect(await manager.log(action: action) == false)

        // echo of the commanded value (50%) confirms → kept
        let echo = EntityStorageItem(entityId: brightnessId, brightness: 50)
        #expect(await manager.invalidateContradictedCommands(for: echo).isEmpty)
        #expect(await manager.log(action: action) == true)

        // a real drift to 10% contradicts → invalidated
        let drift = EntityStorageItem(entityId: brightnessId, brightness: 10)
        #expect(await manager.invalidateContradictedCommands(for: drift) == [action])
        #expect(await manager.log(action: action) == false)
    }

    @Test("State change for an entity with no cached command is a no-op")
    func noCachedCommand() async {
        let manager = ActionLogManager()
        let drift = EntityStorageItem(entityId: switchId, isDeviceOn: false)
        #expect(await manager.invalidateContradictedCommands(for: drift).isEmpty)
    }

    @Test("Only the contradicted command is reset; others for the same entity survive")
    func onlyContradictedIsReset() async {
        let manager = ActionLogManager()
        let onAction = HomeManagableAction.turnOn(switchId)
        let brightnessAction = HomeManagableAction.setBrightness(switchId, 0.5)

        #expect(await manager.log(action: onAction) == false)
        #expect(await manager.log(action: brightnessAction) == false)

        // Only the power state drifted (off); brightness is unknown in this update.
        let drift = EntityStorageItem(entityId: switchId, isDeviceOn: false)
        let invalidated = await manager.invalidateContradictedCommands(for: drift)
        #expect(invalidated == [onAction])

        // turnOn may be re-issued, setBrightness is still deduped.
        #expect(await manager.log(action: onAction) == false)
        #expect(await manager.log(action: brightnessAction) == true)
    }

    @Test("Expired cache entries are dropped and the index self-heals")
    func indexPrunedOnExpiry() async {
        final class DateHolder: @unchecked Sendable {
            var currentDate = Date()
        }
        let holder = DateHolder()
        let manager = ActionLogManager(dateProvider: { holder.currentDate })
        let action = HomeManagableAction.turnOn(switchId)

        #expect(await manager.log(action: action) == false)

        // Advance past the 2-minute TTL so the cache entry expires.
        holder.currentDate = holder.currentDate.addingTimeInterval(121)

        // The contradicting state finds nothing to invalidate (entry already expired).
        let drift = EntityStorageItem(entityId: switchId, isDeviceOn: false)
        #expect(await manager.invalidateContradictedCommands(for: drift).isEmpty)

        // Dedup is gone (expired) → the command is a fresh miss again.
        #expect(await manager.log(action: action) == false)
    }
}
