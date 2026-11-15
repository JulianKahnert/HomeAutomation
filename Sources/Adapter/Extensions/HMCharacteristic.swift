//
//  HMCharacteristic.swift
//  Adapter
//
//  Created by Julian Kahnert on 21.07.24.
//

#if canImport(HomeKit)
import HAModels
import HomeKit
import Logging
import Synchronization

let homeKitLogger = Logger(label: "HomeKitExtensions")

/// Characteristics already logged as dropped, so each one is logged once per launch and not on every refresh.
private let droppedCharacteristicIds = Mutex<Set<UUID>>([])

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

        guard let entityId else {
            logDroppedOnce()
            return nil
        }
        guard isReadable else {
            homeKitLogger.error("Characteristic is not readable", metadata: logMetadata)
            return nil
        }
        do {
            let motionDetected = try await hasMotion()
            let illuminance = try await getIlluminance()
            let isDeviceOn = try await isDeviceOn()
            let brightness = try await getBrightness()
            let colorTemperature = try await getColorTemperature()
            let color = try await getColor()
            let isContactOpen = try await isContactOpen()
            let isDoorLocked = try await isDoorLocked()
            let stateOfCharge = try await getStateOfCharge()
            let isHeaterActive = try await getHeaterState()
            let temperature = try await getTemperature()
            let relativeHumidity = try await getRelativeHumidity()
            let carbonDioxideLevel = try await getCarbonDioxideLevel()
            let pmDensity = try await getPMDensity()
            let airQuality = try await getAirQuality()
            let valveOpen = try await getValveOpen()
            let targetTemperature = try await getTargetTemperature()
            let heatingMode = try await getHeatingMode()
            let valvePositionPercent = try await getValvePositionPercent()

            let item = EntityStorageItem(entityId: entityId,
                                     timestamp: timestamp,
                                     motionDetected: motionDetected,
                                     illuminance: illuminance,
                                     isDeviceOn: isDeviceOn,
                                     brightness: brightness,
                                     colorTemperature: colorTemperature,
                                     color: color,
                                     isContactOpen: isContactOpen,
                                     isDoorLocked: isDoorLocked,
                                     stateOfCharge: stateOfCharge,
                                     isHeaterActive: isHeaterActive,
                                     temperatureInC: temperature,
                                     relativeHumidity: relativeHumidity,
                                     carbonDioxideSensorId: carbonDioxideLevel,
                                     pmDensity: pmDensity,
                                     airQuality: airQuality,
                                     valveOpen: valveOpen,
                                     targetTemperatureInC: targetTemperature,
                                     heatingMode: heatingMode,
                                     valvePositionPercent: valvePositionPercent)
            if entityId.characteristicType.isHeatingRelated {
                homeKitLogger.debug("Read heating characteristic", metadata: logMetadata.merging([
                    "entityType": "\(entityId.characteristicType)",
                    "isHeaterActive": "\(isHeaterActive.map(String.init(describing:)) ?? "nil")",
                    "targetTemperatureInC": "\(targetTemperature.map(String.init(describing:)) ?? "nil")",
                    "heatingMode": "\(heatingMode?.name ?? "nil")",
                    "valvePositionPercent": "\(valvePositionPercent.map(String.init(describing:)) ?? "nil")"
                ]) { _, new in new })
            }
            return item
        } catch {
            // this might occur when e.g. the IKEA hub or a device is not available
            homeKitLogger.warning("Error while getting characteristic data - \(self.service?.accessory?.room?.name ?? "")@\(self.service?.accessory?.name ?? "") - \(self)\n\(error)")
            return nil
        }
    }

    /// Room, accessory, service and characteristic, with their HomeKit type UUIDs, for log metadata.
    var logMetadata: Logger.Metadata {
        [
            "room": "\(service?.accessory?.room?.name ?? "")",
            "accessory": "\(service?.accessory?.name ?? "")",
            "service": "\(service?.name ?? "")",
            "serviceType": "\(service?.serviceType ?? "")",
            "characteristic": "\(localizedDescription)",
            "characteristicType": "\(characteristicType)",
            "characteristicId": "\(uniqueIdentifier.uuidString)"
        ]
    }

    /// Logs once per characteristic that it has no entity id and is never sent to the server.
    private func logDroppedOnce() {
        let isFirstDrop = droppedCharacteristicIds.withLock { $0.insert(uniqueIdentifier).inserted }
        guard isFirstDrop else { return }
        // Most dropped characteristics are expected (firmware version, name, ...); a thermostat's
        // are not, because their history silently stays empty.
        let isUnexpected = HeatingControlCharacteristic.isHeatingService(service?.serviceType) || entityCharacteristicType != nil
        homeKitLogger.log(level: isUnexpected ? .notice : .debug, "Dropped characteristic without entity id", metadata: logMetadata)
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

        guard let illuminance = value as? Double else {
            assertionFailure("Illuminance characteristic value is not Double - value: \(String(describing: value))")
            return nil
        }
        return .init(value: illuminance, unit: .lux)
    }

    private func isDeviceOn() async throws -> Bool? {
        guard // let service,
              // We don't specify the servicType, because there might be other/new services which could be turned off
              // service.serviceType == HMServiceTypeLightbulb || service.serviceType == HMServiceTypeSwitch || service.serviceType == HMServiceTypeOutlet,
              characteristicType == HMCharacteristicTypePowerState,
              metadata?.format == HMCharacteristicMetadataFormatBool else { return nil }

        try await readValue()

        guard let value = value as? Bool else {
            assertionFailure("PowerState characteristic value is not Bool - value: \(String(describing: value))")
            return nil
        }
        return value
    }

    private func isContactOpen() async throws -> Bool? {
        guard let service,
              service.serviceType == HMServiceTypeContactSensor,
              characteristicType == HMCharacteristicTypeContactState else { return nil }

        try await readValue()

        guard let value = value as? Int,
              let contactState = HMCharacteristicValueContactState(rawValue: value) else {
            assertionFailure("ContactState characteristic value is not valid - value: \(String(describing: value))")
            return nil
        }

        return contactState != .detected
    }

    private func isDoorLocked() async throws -> Bool? {
        guard let service,
              service.serviceType == HMServiceTypeLockMechanism,
              characteristicType == HMCharacteristicTypeTargetLockMechanismState else { return nil }

        try await readValue()

        guard let value = value as? Int,
              let contactState = HMCharacteristicValueLockMechanismState(rawValue: value) else {
            assertionFailure("LockMechanismState characteristic value is not valid - value: \(String(describing: value))")
            return nil
        }

        return contactState == .secured
    }

    private func getStateOfCharge() async throws -> Int? {
        guard let service,
              service.serviceType == HMServiceTypeBattery,
              characteristicType == HMCharacteristicTypeBatteryLevel else { return nil }

        try await readValue()

        guard let stateOfCharge = value as? Int64 else {
            assertionFailure("BatteryLevel characteristic value is not Int64 - value: \(String(describing: value))")
            return nil
        }

        return Int(stateOfCharge)
    }

    private func getHeaterState() async throws -> Bool? {
        guard let service,
              service.serviceType == HMServiceTypeHeaterCooler,
              characteristicType == HMCharacteristicTypeActive else { return nil }

        try await readValue()

        guard let rawValue = value as? Int,
              let state = HMCharacteristicValueActivationState(rawValue: rawValue) else {
            assertionFailure("Active characteristic value is not valid - value: \(String(describing: value))")
            return nil
        }

        return state == .active
    }

    private func getBrightness() async throws -> Int? {
        guard characteristicType == HMCharacteristicTypeBrightness else { return nil }

        try await readValue()

        guard let brightness = value as? Int else {
            assertionFailure("Brightness characteristic value is not Int - value: \(String(describing: value))")
            return nil
        }
        return brightness
    }

    private func getColorTemperature() async throws -> Float? {
        guard characteristicType == HMCharacteristicTypeColorTemperature else { return nil }

        try await readValue()

        // HomeKit returns color temperature in mired (micro-reciprocal degrees)
        // Normalize to 0...1 (warm...cold) using the same logic as setColorTemperature
        guard let mired = value as? Int,
              let minimumValue = metadata?.minimumValue,
              let maximumValue = metadata?.maximumValue else {
            assertionFailure("ColorTemperature characteristic missing required data - value: \(String(describing: value)), min: \(String(describing: metadata?.minimumValue)), max: \(String(describing: metadata?.maximumValue))")
            return nil
        }

        let min = Float(truncating: minimumValue)
        let max = Float(truncating: maximumValue)
        let range = max - min

        guard range > 0 else {
            assertionFailure("ColorTemperature characteristic has invalid range - min: \(min), max: \(max), range: \(range)")
            return nil
        }

        // Invert because lower mired = colder light, but we want 0 = warm, 1 = cold
        let normalized = 1 - (Float(mired) - min) / range
        return normalized
    }

    private func getColor() async throws -> RGB? {
        guard let service,
              characteristicType == HMCharacteristicTypeHue else { return nil }

        try await readValue()
        guard let hue = value as? Float else {
            assertionFailure("Hue characteristic value is not Float - value: \(String(describing: value))")
            return nil
        }

        // Find saturation and brightness characteristics in the same service
        var saturation: Float = 1.0
        var brightness: Float = 1.0

        for characteristic in service.characteristics {
            if characteristic.characteristicType == HMCharacteristicTypeSaturation {
                try await characteristic.readValue()
                saturation = (characteristic.value as? Float ?? 100.0) / 100.0
            } else if characteristic.characteristicType == HMCharacteristicTypeBrightness {
                try await characteristic.readValue()
                brightness = (characteristic.value as? Float ?? 100.0) / 100.0
            }
        }

        // Convert HSV to RGB using the utility function
        let normalizedHue = hue / 360.0  // Normalize 0-360° to 0-1
        return rgb(h: normalizedHue, s: saturation, v: brightness)
    }

    private func getTemperature() async throws -> Measurement<UnitTemperature>? {
        guard characteristicType == HMCharacteristicTypeCurrentTemperature else { return nil }

        try await readValue()

        guard let temperature = value as? Double else {
            assertionFailure("Temperature characteristic value is not Float - value: \(String(describing: value))")
            return nil
        }
        return .init(value: temperature, unit: .celsius)
    }

    private func getRelativeHumidity() async throws -> Double? {
        guard characteristicType == HMCharacteristicTypeCurrentRelativeHumidity else { return nil }

        try await readValue()

        guard let humidity = value as? Double else {
            assertionFailure("RelativeHumidity characteristic value is not Float - value: \(String(describing: value))")
            return nil
        }
        return humidity
    }

    private func getCarbonDioxideLevel() async throws -> Int? {
        guard characteristicType == HMCharacteristicTypeCarbonDioxideLevel else { return nil }

        try await readValue()

        guard let co2Level = value as? Float else {
            assertionFailure("CarbonDioxideLevel characteristic value is not Float - value: \(String(describing: value))")
            return nil
        }
        return Int(co2Level)
    }

    private func getPMDensity() async throws -> Double? {
        guard characteristicType == HMCharacteristicTypePM2_5Density else { return nil }

        try await readValue()

        guard let density = value as? Float else {
            assertionFailure("PMDensity characteristic value is not Float - value: \(String(describing: value))")
            return nil
        }
        return Double(density)
    }

    private func getAirQuality() async throws -> Int? {
        guard characteristicType == HMCharacteristicTypeAirQuality else { return nil }

        try await readValue()

        guard let quality = value as? Int else {
            assertionFailure("AirQuality characteristic value is not Int - value: \(String(describing: value))")
            return nil
        }
        return quality
    }

    private func getValveOpen() async throws -> Bool? {
        guard let service,
              service.serviceType == HMServiceTypeValve,
              characteristicType == HMCharacteristicTypeActive else { return nil }

        try await readValue()

        guard let rawValue = value as? Int,
              let state = HMCharacteristicValueActivationState(rawValue: rawValue) else {
            assertionFailure("Active characteristic value is not valid - value: \(String(describing: value))")
            return nil
        }

        return state == .active
    }

    /// Thermostat `TargetTemperature` or HeaterCooler `HeatingThresholdTemperature`.
    private func getTargetTemperature() async throws -> Double? {
        guard HeatingControlCharacteristic.characteristicsType(characteristicType: characteristicType,
                                                               serviceType: service?.serviceType) == .targetTemperature else { return nil }

        try await readValue()

        guard let target = (value as? NSNumber)?.doubleValue else {
            assertionFailure("Target temperature characteristic value is not a number - value: \(String(describing: value))")
            return nil
        }
        return target
    }

    /// Thermostat `TargetHeatingCoolingState` or HeaterCooler `TargetHeaterCoolerState`.
    private func getHeatingMode() async throws -> HeatingMode? {
        guard HeatingControlCharacteristic.characteristicsType(characteristicType: characteristicType,
                                                               serviceType: service?.serviceType) == .heatingMode else { return nil }

        try await readValue()

        guard let rawMode = (value as? NSNumber)?.intValue else {
            assertionFailure("Target mode characteristic value is not a number - value: \(String(describing: value))")
            return nil
        }
        guard let heatingMode = HeatingControlCharacteristic.heatingMode(rawValue: rawMode, characteristicType: characteristicType) else {
            homeKitLogger.warning("Unknown target mode value, stored as nil", metadata: logMetadata.merging(["rawValue": "\(rawMode)"]) { _, new in new })
            return nil
        }
        return heatingMode
    }

    /// Eve custom characteristic, matched by UUID because HomeKit reports it as "Custom".
    private func getValvePositionPercent() async throws -> Int? {
        guard EveCharacteristic.isValvePosition(characteristicType) else { return nil }

        try await readValue()

        guard let percent = (value as? NSNumber)?.intValue else {
            homeKitLogger.warning("Eve valve position value is not a number - value: \(String(describing: value))")
            return nil
        }
        return percent
    }

    var entityId: EntityId? {
        guard let placeId = service?.accessory?.room?.name,
              let name = service?.accessory?.name,
              let characteristicType = entityCharacteristicType else { return nil }
        return EntityId(placeId: placeId, name: name, characteristicsName: service?.name, characteristic: characteristicType)
    }

    var shouldSubscribe: Bool {
        // false if we don't know the characteristic
        entityCharacteristicType?.isSubscribed ?? false
    }

    private static let skippableCharacteristics = Set(["Active", "Camera Operating Mode Indicator", "Charging State", "Configured Name", "Cooling Threshold Temperature", "Current Heater Cooler State", "Current Heating Cooling State", "Custom", "Event Snapshots Active", "Firmware Version", "Hardware Version", "In Use", "Is Configured", "Label Index", "Lock Mechanism Current State", "Lock Mechanism Target State", "Lock Physical Controls", "Manufacturer", "Model", "Mute", "Name", "Night Vision", "Outlet In Use", "Program Mode", "Recording Audio Active", "Remaining Duration", "Saturation", "Serial Number", "Set Duration", "Software Version", "Status Active", "Status Fault", "Status Low Battery", "Temperature Display Units", "Valve Type", "Volatile Organic Compound Density", "Volume", "Programmable Switch Event", "Smoke Detected", "Leak Detected", "Status Tampered"])
    var entityCharacteristicType: CharacteristicsType? {
        guard let homeKitCharacteristic = HomeKitCharacteristic(characteristicType: characteristicType) else {
            guard !Self.skippableCharacteristics.contains(localizedDescription) else { return nil }
            homeKitLogger.warning("Failed to get entity characteristic type", metadata: logMetadata)
            assertionFailure()
            return nil
        }
        return homeKitCharacteristic.toCharacteristicsType(serviceType: service?.serviceType)
    }
}
#endif
