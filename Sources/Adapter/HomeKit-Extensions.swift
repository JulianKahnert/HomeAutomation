//
//  Extensions.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 21.07.24.
//

#if canImport(HomeKit)
import HAModels
import HomeKit
import Logging

let homeKitLogger = Logger(label: "HomeKitExtensions")
extension HMCharacteristic: @retroactive Comparable {
    public static func < (lhs: HMCharacteristic, rhs: HMCharacteristic) -> Bool {
        if lhs.service?.accessory?.room?.name ?? "" != rhs.service?.accessory?.room?.name ?? "" {
            return lhs.service?.accessory?.room?.name ?? "" < rhs.service?.accessory?.room?.name ?? ""
        } else if lhs.service?.accessory?.name ?? "" != rhs.service?.accessory?.name ?? "" {
            return lhs.service?.accessory?.name ?? "" < rhs.service?.accessory?.name ?? ""
        } else if lhs.service?.name ?? "" != rhs.service?.name ?? "" {
            return lhs.service?.name ?? "" < rhs.service?.name ?? ""
        }

        return lhs.characteristicType < rhs.characteristicType
    }

    override open var description: String {
        "\(service?.name ?? ""): \(localizedDescription) (\(self.uniqueIdentifier.uuidString))"
    }

    var isReadable: Bool {
        return properties.contains(HMCharacteristicPropertyReadable)
    }

    var isNotifiable: Bool {
        return properties.contains(HMCharacteristicPropertySupportsEventNotification)
    }

    func getEntityStorageItem() async -> EntityStorageItem? {
        let timestamp = Date() // since we have no better date when this changed, so we use this date here

        guard let entityId,
              isReadable else {
            homeKitLogger.error("Characteristic is not readable\n\(self)")
            return nil
        }
        do {
            let motionDetected = try await hasMotion()
            let illuminance = try await getIlluminance()
            let isDeviceOn = try await isDeviceOn()
            let isContactOpen = try await isContactOpen()
            let isDoorLocked = try await isDoorLocked()
            let stateOfCharge = try await getStateOfCharge()
            let isHeaterActive = try await getHeaterState()

            return EntityStorageItem(entityId: entityId,
                                     timestamp: timestamp,
                                     motionDetected: motionDetected,
                                     illuminance: illuminance,
                                     isDeviceOn: isDeviceOn,
                                     isContactOpen: isContactOpen,
                                     isDoorLocked: isDoorLocked,
                                     stateOfCharge: stateOfCharge,
                                     isHeaterActive: isHeaterActive)
        } catch {
            // this might occur when e.g. the IKEA hub or a device is not available
            homeKitLogger.critical("Error while getting characteristic data - \(self.service?.accessory?.room?.name ?? "")@\(self.service?.accessory?.name ?? "") - \(self)\n\(error)")
            return EntityStorageItem(entityId: entityId)
        }
    }

    private func hasMotion() async throws -> Bool? {
        guard let service else { return nil }

        if service.serviceType == HMServiceTypeOccupancySensor,
           characteristicType == HMCharacteristicTypeOccupancyDetected {

            try await readValue()

            let motionDetected = (value as? Int64) == 1
            return motionDetected

        } else if service.serviceType == HMServiceTypeMotionSensor,
                  characteristicType == HMCharacteristicTypeMotionDetected {

            try await readValue()

            let motionDetected = value as? Bool
            return motionDetected
        } else {
            return nil
        }
    }

    private func getIlluminance() async throws -> Measurement<UnitIlluminance>? {
        guard let service,
              service.serviceType == HMServiceTypeLightSensor,
              characteristicType == HMCharacteristicTypeCurrentLightLevel else { return nil }

        try await readValue()

        guard let illuminance = value as? Double else { return nil }
        return .init(value: illuminance, unit: .lux)
    }

    private func isDeviceOn() async throws -> Bool? {
        guard // let service,
              // We don't specify the servicType, because there might be other/new services which could be turned off
              // service.serviceType == HMServiceTypeLightbulb || service.serviceType == HMServiceTypeSwitch || service.serviceType == HMServiceTypeOutlet,
              characteristicType == HMCharacteristicTypePowerState,
              metadata?.format == HMCharacteristicMetadataFormatBool else { return nil }

        try await readValue()

        guard let value = value as? Bool else { return nil }
        return value
    }

    private func isContactOpen() async throws -> Bool? {
        guard let service,
              service.serviceType == HMServiceTypeContactSensor,
              characteristicType == HMCharacteristicTypeContactState else { return nil }

        try await readValue()

        guard let value = value as? Int,
              let contactState = HMCharacteristicValueContactState(rawValue: value) else { return nil }

        return contactState != .detected
    }

    private func isDoorLocked() async throws -> Bool? {
        guard let service,
              service.serviceType == HMServiceTypeLockMechanism,
              characteristicType == HMCharacteristicTypeTargetLockMechanismState else { return nil }

        try await readValue()

        guard let value = value as? Int,
              let contactState = HMCharacteristicValueLockMechanismState(rawValue: value) else { return nil }

        return contactState == .secured
    }

    private func getStateOfCharge() async throws -> Int? {
        guard let service,
              service.serviceType == HMServiceTypeBattery,
              characteristicType == HMCharacteristicTypeBatteryLevel else { return nil }

        try await readValue()

        guard let stateOfCharge = value as? Int64 else { return nil }

        return Int(stateOfCharge)
    }

    private func getHeaterState() async throws -> Bool? {
        guard let service,
              service.serviceType == HMServiceTypeHeaterCooler,
              characteristicType == HMCharacteristicTypeActive else { return nil }

        try await readValue()

        guard let isHeatingActive = value as? Bool else { return nil }

        return isHeatingActive
    }

    func isCharacteristicsType(_ type: CharacteristicsType) -> Bool {
        switch type {
        case .batterySensor:
            return characteristicType == HMCharacteristicTypeBatteryLevel
        case .contactSensor:
            return characteristicType == HMCharacteristicTypeContactState
        case .lightSensor:
            return characteristicType == HMCharacteristicTypeCurrentLightLevel
        case .motionSensor:
            return characteristicType == HMCharacteristicTypeMotionDetected || characteristicType == HMCharacteristicTypeOccupancyDetected
        case .brightness:
            return characteristicType == HMCharacteristicTypeBrightness
        case .colorTemperature:
            return characteristicType == HMCharacteristicTypeColorTemperature
        case .color:
            return characteristicType == HMCharacteristicTypeHue
        case .switcher:
            return characteristicType == HMCharacteristicTypePowerState
        case .valve:
            return service?.serviceType == HMServiceTypeValve && characteristicType == HMCharacteristicTypeInUse
        case .lock:
            return characteristicType == HMCharacteristicTypeTargetLockMechanismState
        case .heating:
            return service?.serviceType == HMServiceTypeHeaterCooler && characteristicType == HMCharacteristicTypeActive
        }
    }

    var entityId: EntityId? {
        guard let placeId = service?.accessory?.room?.name,
              let name = service?.accessory?.name,
              let characteristicType = entityCharacteristicType else { return nil }
        return EntityId(placeId: placeId, name: name, characteristicsName: service?.name, characteristic: characteristicType)
    }

    var shouldSubscribe: Bool {
        guard let type = entityCharacteristicType else { return false }

        switch type {
        case .motionSensor, .lightSensor, .switcher, .contactSensor:
            return true
        case .batterySensor, .brightness, .colorTemperature, .color, .heating, .valve, .lock:
            return false
        }
    }

    private static let skippableCharacteristics = Set(["Active", "Air Quality", "Camera Operating Mode Indicator", "Charging State", "Configured Name", "Current Heater Cooler State", "Current Heating Cooling State", "Current Relative Humidity", "Current Temperature", "Custom", "Event Snapshots Active", "Firmware Version", "Hardware Version", "Heating Threshold Temperature", "In Use", "Is Configured", "Label Index", "Lock Mechanism Current State", "Lock Mechanism Target State", "Lock Physical Controls", "Manufacturer", "Model", "Mute", "Name", "Night Vision", "Outlet In Use", "Program Mode", "Recording Audio Active", "Remaining Duration", "Saturation", "Serial Number", "Set Duration", "Software Version", "Status Active", "Status Fault", "Status Low Battery", "Target Heater Cooler State", "Target Heating Cooling State", "Target Temperature", "Temperature Display Units", "Valve Type", "Volatile Organic Compound Density", "Volume", "Programmable Switch Event"])
    var entityCharacteristicType: CharacteristicsType? {
        if characteristicType == HMCharacteristicTypeMotionDetected || characteristicType == HMCharacteristicTypeOccupancyDetected {
            return .motionSensor

        } else if characteristicType == HMCharacteristicTypeCurrentLightLevel {
            return .lightSensor

        } else if characteristicType == HMCharacteristicTypeBatteryLevel {
            return .batterySensor

        } else if characteristicType == HMCharacteristicTypeContactState {
            return .contactSensor

        } else if characteristicType == HMCharacteristicTypePowerState {
            return .switcher

        } else if characteristicType == HMCharacteristicTypeBrightness {
            return .brightness

        } else if characteristicType == HMCharacteristicTypeColorTemperature {
            return .colorTemperature

        } else if characteristicType == HMCharacteristicTypeHue {
            return .color

        } else if service?.serviceType == HMServiceTypeValve && characteristicType == HMCharacteristicTypeInUse {
            return .valve

        } else if service?.serviceType == HMServiceTypeHeaterCooler && characteristicType == HMCharacteristicTypeActive {
            return .heating

        } else {
            guard !Self.skippableCharacteristics.contains(localizedDescription) else { return nil }
            homeKitLogger.warning("Failed to get entity characteristic type for \(self.service?.name ?? "") @ \(self.service?.accessory?.room?.name ?? ""): \(self.localizedDescription)")
            return nil
        }
    }
}

extension HMAction {
    var characteristic: HMCharacteristic? {
        value(forKey: "characteristic") as? HMCharacteristic
    }
}

extension HMAccessory {
    var home: HMHome? {
        value(forKey: "home") as? HMHome
    }
}

extension HMActionSet {
    var home: HMHome? {
        value(forKey: "home") as? HMHome
    }
}
#endif
