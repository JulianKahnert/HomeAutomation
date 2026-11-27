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

        guard let entityId else {
            // Classified once per setup in the `Characteristic found` log; this runs on every refresh.
            homeKitLogger.debug("Skipped characteristic without entity id", metadata: logMetadata)
            return nil
        }
        guard isReadable else {
            homeKitLogger.error("Characteristic is not readable", metadata: logMetadata)
            return nil
        }
        let type = entityId.characteristicType
        let context = HomeKitValueMapping.Context(
            serviceType: service?.serviceType,
            characteristicType: characteristicType,
            isBoolFormat: metadata?.format == HMCharacteristicMetadataFormatBool,
            minimumValue: metadata?.minimumValue?.doubleValue,
            maximumValue: metadata?.maximumValue?.doubleValue
        )
        guard HomeKitValueMapping.needsRead(type, context: context) else {
            return EntityStorageItem(entityId: entityId, timestamp: timestamp)
        }
        do {
            try await readValue()
            var context = context
            if type == .color {
                (context.saturation, context.brightness) = try await colorSiblingValues()
            }
            guard let mapped = HomeKitValueMapping.value(type, raw: value, context: context) else {
                if type == .heatingMode || type == .valvePosition {
                    homeKitLogger.warning("Unusable heating characteristic value, stored as nil", metadata: logMetadata.merging(["rawValue": "\(String(describing: value))"]) { _, new in new })
                } else {
                    assertionFailure("\(type) characteristic value is not valid - value: \(String(describing: value)), min: \(String(describing: metadata?.minimumValue)), max: \(String(describing: metadata?.maximumValue))")
                }
                return EntityStorageItem(entityId: entityId, timestamp: timestamp)
            }
            guard let item = EntityStorageItem(entityId: entityId, timestamp: timestamp, value: mapped) else {
                assertionFailure("\(type) characteristic value does not fit its kind - value: \(mapped)")
                return EntityStorageItem(entityId: entityId, timestamp: timestamp)
            }
            if type.isHeatingRelated {
                homeKitLogger.debug("Read heating characteristic", metadata: logMetadata.merging([
                    "entityType": "\(type)",
                    "value": "\(mapped)"
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

    /// The `Saturation` and `Brightness` values of the service, which a colour is made of together with the hue.
    private func colorSiblingValues() async throws -> (saturation: Any?, brightness: Any?) {
        var saturation: Any?
        var brightness: Any?
        for characteristic in service?.characteristics ?? [] {
            if characteristic.characteristicType == HMCharacteristicTypeSaturation {
                try await characteristic.readValue()
                saturation = characteristic.value
            } else if characteristic.characteristicType == HMCharacteristicTypeBrightness {
                try await characteristic.readValue()
                brightness = characteristic.value
            }
        }
        return (saturation, brightness)
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
