//
//  CommandCacheTests.swift
//  HomeAutomationKit
//
//  Created by Claude Code on 21.06.26.
//

import Foundation
@testable import HAApplicationLayer
import HAModels
import Testing

struct CommandCacheTests {

    private let switchId = EntityId(placeId: "room", name: "light", characteristicsName: nil, characteristic: .switcher)
    private let brightnessId = EntityId(placeId: "room", name: "light", characteristicsName: nil, characteristic: .brightness)

    @Test("Confirming echo does not invalidate — dedup is preserved (no command storm)")
    func echoPreservesDedup() async {
        let manager = CommandCache()
        let action = HomeManagableAction.turnOn(switchId)

        #expect(await manager.isDuplicate(action) == false) // first call: miss
        await manager.markExecuted(action) // command reached the device → cached

        let echo = EntityStorageItem(entityId: switchId, isDeviceOn: true)
        let invalidated = await manager.invalidateContradictedCommands(for: echo)
        #expect(invalidated.isEmpty)

        #expect(await manager.isDuplicate(action) == true) // still deduped
    }

    @Test("Contradicting state invalidates — command may be re-issued")
    func driftInvalidates() async {
        let manager = CommandCache()
        let action = HomeManagableAction.turnOn(switchId)

        #expect(await manager.isDuplicate(action) == false)
        await manager.markExecuted(action)

        let drift = EntityStorageItem(entityId: switchId, isDeviceOn: false)
        let invalidated = await manager.invalidateContradictedCommands(for: drift)
        #expect(invalidated == [action])

        #expect(await manager.isDuplicate(action) == false) // re-issue allowed (cache miss)
    }

    @Test("setBrightness echo preserves dedup, drift invalidates")
    func brightnessDrift() async {
        let manager = CommandCache()
        let action = HomeManagableAction.setBrightness(brightnessId, 0.5)

        #expect(await manager.isDuplicate(action) == false)
        await manager.markExecuted(action)

        // echo of the commanded value (50%) confirms → kept
        let echo = EntityStorageItem(entityId: brightnessId, brightness: 50)
        #expect(await manager.invalidateContradictedCommands(for: echo).isEmpty)
        #expect(await manager.isDuplicate(action) == true)

        // a real drift to 10% contradicts → invalidated
        let drift = EntityStorageItem(entityId: brightnessId, brightness: 10)
        #expect(await manager.invalidateContradictedCommands(for: drift) == [action])
        #expect(await manager.isDuplicate(action) == false)
    }

    @Test("A logged but unexecuted command stays a cache miss")
    func unexecutedCommandIsNotDeduped() async {
        let manager = CommandCache()
        let action = HomeManagableAction.turnOn(switchId)

        // The command never reached the device (cancelled, adapter error) — the next attempt must
        // get through.
        #expect(await manager.isDuplicate(action) == false)
        #expect(await manager.isDuplicate(action) == false)
    }

    @Test("markExecuted makes an identical command a cache hit")
    func executedCommandIsDeduped() async {
        let manager = CommandCache()
        let action = HomeManagableAction.setBrightness(brightnessId, 0.5)

        #expect(await manager.isDuplicate(action) == false)
        await manager.markExecuted(action)

        #expect(await manager.isDuplicate(action) == true)
        // a different value for the same entity + action kind is not a duplicate
        #expect(await manager.isDuplicate(.setBrightness(brightnessId, 0.8)) == false)
    }

    @Test("State change for an entity with no cached command is a no-op")
    func noCachedCommand() async {
        let manager = CommandCache()
        let drift = EntityStorageItem(entityId: switchId, isDeviceOn: false)
        #expect(await manager.invalidateContradictedCommands(for: drift).isEmpty)
    }

    @Test("Only the contradicted command is reset; others for the same entity survive")
    func onlyContradictedIsReset() async {
        let manager = CommandCache()
        let onAction = HomeManagableAction.turnOn(switchId)
        let brightnessAction = HomeManagableAction.setBrightness(switchId, 0.5)

        #expect(await manager.isDuplicate(onAction) == false)
        await manager.markExecuted(onAction)
        #expect(await manager.isDuplicate(brightnessAction) == false)
        await manager.markExecuted(brightnessAction)

        // Only the power state drifted (off); brightness is unknown in this update.
        let drift = EntityStorageItem(entityId: switchId, isDeviceOn: false)
        let invalidated = await manager.invalidateContradictedCommands(for: drift)
        #expect(invalidated == [onAction])

        // turnOn may be re-issued, setBrightness is still deduped.
        #expect(await manager.isDuplicate(onAction) == false)
        #expect(await manager.isDuplicate(brightnessAction) == true)
    }

    @Test("Expired cache entries are dropped and the index self-heals")
    func indexPrunedOnExpiry() async {
        final class DateHolder: @unchecked Sendable {
            var currentDate = Date()
        }
        let holder = DateHolder()
        let manager = CommandCache(dateProvider: { holder.currentDate })
        let action = HomeManagableAction.turnOn(switchId)

        #expect(await manager.isDuplicate(action) == false)
        await manager.markExecuted(action)

        // Advance past the 2-minute TTL so the cache entry expires.
        holder.currentDate = holder.currentDate.addingTimeInterval(121)

        // The contradicting state finds nothing to invalidate (entry already expired).
        let drift = EntityStorageItem(entityId: switchId, isDeviceOn: false)
        #expect(await manager.invalidateContradictedCommands(for: drift).isEmpty)

        // Dedup is gone (expired) → the command is a fresh miss again.
        #expect(await manager.isDuplicate(action) == false)
    }
}
