//
//  HomeKitCharacteristic.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 20.12.24.
//

#if canImport(HomeKit)
import HAModels
import HomeKit

/// Mapping layer from HomeKit characteristic types to our domain model
enum HomeKitCharacteristic {
    case batteryLevel
    case contactState
    case currentLightLevel
    case motionDetected
    case occupancyDetected
    case brightness
    case colorTemperature
    case hue
    case powerState
    case inUse
    case active
    case targetLockMechanismState
    case currentTemperature
    case currentRelativeHumidity
    case carbonDioxideLevel
    case pm2_5Density
    case airQuality

    /// Maps HomeKit characteristic type string to our enum
    init?(characteristicType: String) {
        switch characteristicType {
        case HMCharacteristicTypeBatteryLevel:
            self = .batteryLevel
        case HMCharacteristicTypeContactState:
            self = .contactState
        case HMCharacteristicTypeCurrentLightLevel:
            self = .currentLightLevel
        case HMCharacteristicTypeMotionDetected:
            self = .motionDetected
        case HMCharacteristicTypeOccupancyDetected:
            self = .occupancyDetected
        case HMCharacteristicTypeBrightness:
            self = .brightness
        case HMCharacteristicTypeColorTemperature:
            self = .colorTemperature
        case HMCharacteristicTypeHue:
            self = .hue
        case HMCharacteristicTypePowerState:
            self = .powerState
        case HMCharacteristicTypeInUse:
            self = .inUse
        case HMCharacteristicTypeActive:
            self = .active
        case HMCharacteristicTypeTargetLockMechanismState:
            self = .targetLockMechanismState
        case HMCharacteristicTypeCurrentTemperature:
            self = .currentTemperature
        case HMCharacteristicTypeCurrentRelativeHumidity:
            self = .currentRelativeHumidity
        case HMCharacteristicTypeCarbonDioxideLevel:
            self = .carbonDioxideLevel
        case HMCharacteristicTypePM2_5Density:
            self = .pm2_5Density
        case HMCharacteristicTypeAirQuality:
            self = .airQuality
        default:
            return nil
        }
    }

    /// Maps to domain model CharacteristicsType, considering service type for context-dependent mappings
    func toCharacteristicsType(serviceType: String?) -> CharacteristicsType? {
        switch self {
        case .batteryLevel:
            return .batterySensor
        case .contactState:
            return .contactSensor
        case .currentLightLevel:
            return .lightSensor
        case .motionDetected, .occupancyDetected:
            return .motionSensor
        case .brightness:
            return .brightness
        case .colorTemperature:
            return .colorTemperature
        case .hue:
            return .color
        case .powerState:
            return .switcher
        case .targetLockMechanismState:
            return .lock
        case .currentTemperature:
            return .temperatureSensor
        case .currentRelativeHumidity:
            return .relativeHumiditySensor
        case .carbonDioxideLevel:
            return .carbonDioxideSensorId
        case .pm2_5Density:
            return .pmDensitySensor
        case .airQuality:
            return .airQualitySensor
        case .inUse:
            return serviceType == HMServiceTypeValve ? .valve : nil
        case .active:
            return serviceType == HMServiceTypeHeaterCooler ? .heating : nil
        }
    }
}
#endif
