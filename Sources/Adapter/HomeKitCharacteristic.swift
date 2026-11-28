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
    /// Target temperature or mode on a Thermostat or HeaterCooler service, see `HeatingControlCharacteristic`.
    case heatingControl(characteristicType: String)
    case eveValvePosition

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
        case _ where HeatingControlCharacteristic.isHeatingControl(characteristicType):
            self = .heatingControl(characteristicType: characteristicType)
        case _ where EveCharacteristic.isValvePosition(characteristicType):
            self = .eveValvePosition
        default:
            return nil
        }
    }

    /// Maps to domain model CharacteristicsType. The one place that decides whether a characteristic is an entity:
    /// the service (and for a switch the Bool format) it sits on has to be the one the kind belongs to, otherwise it is
    /// none, instead of an entity that never gets a value.
    func toCharacteristicsType(serviceType: String?, isBoolFormat: Bool) -> CharacteristicsType? {
        switch self {
        case .batteryLevel:
            return serviceType == HMServiceTypeBattery ? .batterySensor : nil
        case .contactState:
            return serviceType == HMServiceTypeContactSensor ? .contactSensor : nil
        case .currentLightLevel:
            return serviceType == HMServiceTypeLightSensor ? .lightSensor : nil
        case .motionDetected:
            return serviceType == HMServiceTypeMotionSensor ? .motionSensor : nil
        case .occupancyDetected:
            return serviceType == HMServiceTypeOccupancySensor ? .motionSensor : nil
        case .brightness:
            return .brightness
        case .colorTemperature:
            return .colorTemperature
        case .hue:
            return .color
        case .powerState:
            return isBoolFormat ? .switcher : nil
        case .targetLockMechanismState:
            return serviceType == HMServiceTypeLockMechanism ? .lock : nil
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
        case .heatingControl(let characteristicType):
            return HeatingControlCharacteristic.characteristicsType(characteristicType: characteristicType, serviceType: serviceType)
        case .eveValvePosition:
            return .valvePosition
        }
    }
}
#endif
