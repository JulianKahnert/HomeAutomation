//
//  HomeManagableActionContradictionTests.swift
//  HomeAutomationKit
//
//  Created by Claude Code on 21.06.26.
//

import Foundation
@testable import HAModels
import Testing

struct HomeManagableActionContradictionTests {

    private func entityId(_ characteristic: CharacteristicsType) -> EntityId {
        EntityId(placeId: "room", name: "device", characteristicsName: nil, characteristic: characteristic)
    }

    // MARK: - turnOn / turnOff

    @Test("turnOn: off contradicts, on confirms, nil is no-op")
    func turnOn() {
        let id = entityId(.switcher)
        let action = HomeManagableAction.turnOn(id)
        #expect(action.isContradicted(by: EntityStorageItem(entityId: id, isDeviceOn: false)) == true)
        #expect(action.isContradicted(by: EntityStorageItem(entityId: id, isDeviceOn: true)) == false)
        #expect(action.isContradicted(by: EntityStorageItem(entityId: id, isDeviceOn: nil)) == false)
    }

    @Test("turnOff: on contradicts, off confirms, nil is no-op")
    func turnOff() {
        let id = entityId(.switcher)
        let action = HomeManagableAction.turnOff(id)
        #expect(action.isContradicted(by: EntityStorageItem(entityId: id, isDeviceOn: true)) == true)
        #expect(action.isContradicted(by: EntityStorageItem(entityId: id, isDeviceOn: false)) == false)
        #expect(action.isContradicted(by: EntityStorageItem(entityId: id, isDeviceOn: nil)) == false)
    }

    // MARK: - lockDoor

    @Test("lockDoor: unlocked contradicts, locked confirms, nil is no-op")
    func lockDoor() {
        let id = entityId(.lock)
        let action = HomeManagableAction.lockDoor(id)
        #expect(action.isContradicted(by: EntityStorageItem(entityId: id, isDoorLocked: false)) == true)
        #expect(action.isContradicted(by: EntityStorageItem(entityId: id, isDoorLocked: true)) == false)
        #expect(action.isContradicted(by: EntityStorageItem(entityId: id, isDoorLocked: nil)) == false)
    }

    // MARK: - setHeating

    @Test("setHeating(active): mismatch contradicts, match confirms, nil is no-op")
    func setHeating() {
        let id = entityId(.heating)
        let activeAction = HomeManagableAction.setHeating(id, active: true)
        #expect(activeAction.isContradicted(by: EntityStorageItem(entityId: id, isHeaterActive: false)) == true)
        #expect(activeAction.isContradicted(by: EntityStorageItem(entityId: id, isHeaterActive: true)) == false)
        #expect(activeAction.isContradicted(by: EntityStorageItem(entityId: id, isHeaterActive: nil)) == false)

        let inactiveAction = HomeManagableAction.setHeating(id, active: false)
        #expect(inactiveAction.isContradicted(by: EntityStorageItem(entityId: id, isHeaterActive: true)) == true)
        #expect(inactiveAction.isContradicted(by: EntityStorageItem(entityId: id, isHeaterActive: false)) == false)
    }

    // MARK: - setValve

    @Test("setValve(active): mismatch contradicts, match confirms, nil is no-op")
    func setValve() {
        let id = entityId(.valve)
        let openAction = HomeManagableAction.setValve(id, active: true)
        #expect(openAction.isContradicted(by: EntityStorageItem(entityId: id, valveOpen: false)) == true)
        #expect(openAction.isContradicted(by: EntityStorageItem(entityId: id, valveOpen: true)) == false)
        #expect(openAction.isContradicted(by: EntityStorageItem(entityId: id, valveOpen: nil)) == false)
    }

    // MARK: - setBrightness (Float 0...1 action vs Int 0...100 state, ±1 band)

    @Test("setBrightness: within ±1 point confirms, beyond contradicts, nil is no-op")
    func setBrightness() {
        let id = entityId(.brightness)
        let action = HomeManagableAction.setBrightness(id, 0.5) // commanded 50%
        // confirming band 49/50/51
        #expect(action.isContradicted(by: EntityStorageItem(entityId: id, brightness: 49)) == false)
        #expect(action.isContradicted(by: EntityStorageItem(entityId: id, brightness: 50)) == false)
        #expect(action.isContradicted(by: EntityStorageItem(entityId: id, brightness: 51)) == false)
        // beyond the band
        #expect(action.isContradicted(by: EntityStorageItem(entityId: id, brightness: 48)) == true)
        #expect(action.isContradicted(by: EntityStorageItem(entityId: id, brightness: 52)) == true)
        #expect(action.isContradicted(by: EntityStorageItem(entityId: id, brightness: 10)) == true)
        // no information
        #expect(action.isContradicted(by: EntityStorageItem(entityId: id, brightness: nil)) == false)
    }

    // MARK: - setColorTemperature (normalized 0...1, 0.02 tolerance)

    @Test("setColorTemperature: within tolerance confirms, beyond contradicts, nil is no-op")
    func setColorTemperature() {
        let id = entityId(.colorTemperature)
        let action = HomeManagableAction.setColorTemperature(id, 0.30)
        #expect(action.isContradicted(by: EntityStorageItem(entityId: id, colorTemperature: 0.30)) == false)
        #expect(action.isContradicted(by: EntityStorageItem(entityId: id, colorTemperature: 0.31)) == false) // 0.01 ≤ 0.02
        #expect(action.isContradicted(by: EntityStorageItem(entityId: id, colorTemperature: 0.34)) == true)  // 0.04 > 0.02
        #expect(action.isContradicted(by: EntityStorageItem(entityId: id, colorTemperature: 0.90)) == true)
        #expect(action.isContradicted(by: EntityStorageItem(entityId: id, colorTemperature: nil)) == false)
    }

    // MARK: - setRGB (hue/saturation space, brightness-decoupled)

    @Test("setRGB: same color confirms, different hue contradicts, nil is no-op")
    func setRGBHue() {
        let id = entityId(.color)
        let red = RGB(red: 1, green: 0, blue: 0)
        let blue = RGB(red: 0, green: 0, blue: 1)
        let action = HomeManagableAction.setRGB(id, rgb: red)
        #expect(action.isContradicted(by: EntityStorageItem(entityId: id, color: red)) == false)
        #expect(action.isContradicted(by: EntityStorageItem(entityId: id, color: blue)) == true)
        #expect(action.isContradicted(by: EntityStorageItem(entityId: id, color: nil)) == false)
    }

    @Test("setRGB: saturation drift contradicts")
    func setRGBSaturation() {
        let id = entityId(.color)
        let saturatedRed = RGB(red: 1, green: 0, blue: 0)
        let pale = RGB(red: 1, green: 0.8, blue: 0.8) // same hue, much lower saturation
        let action = HomeManagableAction.setRGB(id, rgb: saturatedRed)
        #expect(action.isContradicted(by: EntityStorageItem(entityId: id, color: pale)) == true)
    }

    @Test("setRGB: near-black read-back is treated as no information")
    func setRGBBlackIsNoOp() {
        let id = entityId(.color)
        let action = HomeManagableAction.setRGB(id, rgb: RGB(red: 1, green: 0, blue: 0))
        #expect(action.isContradicted(by: EntityStorageItem(entityId: id, color: RGB(red: 0, green: 0, blue: 0))) == false)
    }

    // MARK: - addEntityToScene (no live characteristic)

    @Test("addEntityToScene: never contradicted")
    func addEntityToScene() {
        let id = entityId(.switcher)
        let action = HomeManagableAction.addEntityToScene(id, sceneName: "goodNight", targetValue: .off)
        #expect(action.isContradicted(by: EntityStorageItem(entityId: id, isDeviceOn: true)) == false)
        #expect(action.isContradicted(by: EntityStorageItem(entityId: id, isDeviceOn: false)) == false)
    }
}
