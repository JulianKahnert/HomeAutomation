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

            return EntityStorageItem(entityId: entityId,
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
                                     valveOpen: valveOpen)
        } catch {
            // this might occur when e.g. the IKEA hub or a device is not available
            homeKitLogger.critical("Error while getting characteristic data - \(self.service?.accessory?.room?.name ?? "")@\(self.service?.accessory?.name ?? "") - \(self)\n\(error)")
            return nil
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
        let h = hue / 360.0  // Normalize 0-360° to 0-1
        return rgb(h: h, s: saturation, v: brightness)
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

    var entityId: EntityId? {
        guard let placeId = service?.accessory?.room?.name,
              let name = service?.accessory?.name,
              let characteristicType = entityCharacteristicType else { return nil }
        return EntityId(placeId: placeId, name: name, characteristicsName: service?.name, characteristic: characteristicType)
    }

    var shouldSubscribe: Bool {
        // true if we know the characteristic
        entityCharacteristicType != nil
    }

    private static let skippableCharacteristics = Set(["Active", "Camera Operating Mode Indicator", "Charging State", "Configured Name", "Current Heater Cooler State", "Current Heating Cooling State", "Custom", "Event Snapshots Active", "Firmware Version", "Hardware Version", "Heating Threshold Temperature", "In Use", "Is Configured", "Label Index", "Lock Mechanism Current State", "Lock Mechanism Target State", "Lock Physical Controls", "Manufacturer", "Model", "Mute", "Name", "Night Vision", "Outlet In Use", "Program Mode", "Recording Audio Active", "Remaining Duration", "Saturation", "Serial Number", "Set Duration", "Software Version", "Status Active", "Status Fault", "Status Low Battery", "Target Heater Cooler State", "Target Heating Cooling State", "Target Temperature", "Temperature Display Units", "Valve Type", "Volatile Organic Compound Density", "Volume", "Programmable Switch Event", "Smoke Detected", "Leak Detected"])
    var entityCharacteristicType: CharacteristicsType? {
        guard let homeKitCharacteristic = HomeKitCharacteristic(characteristicType: characteristicType) else {
            guard !Self.skippableCharacteristics.contains(localizedDescription) else { return nil }
            homeKitLogger.warning("Failed to get entity characteristic type for \(self.service?.name ?? "") @ \(self.service?.accessory?.room?.name ?? ""): \(self.localizedDescription)")
            assertionFailure()
            return nil
        }
        return homeKitCharacteristic.toCharacteristicsType(serviceType: service?.serviceType)
    }
}
#endif
