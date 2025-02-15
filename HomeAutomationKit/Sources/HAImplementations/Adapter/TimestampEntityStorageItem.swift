//
//  TimestampEntityStorageItem.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 23.07.24.
//

#if canImport(SwiftData)
import Foundation
import HAModels
import SwiftData

@Model
public final class TimestampEntityStorageItem {
    public var timestamp = Date()
    public var entityPlaceId: String = ""
    public var entityServiceName: String = ""
    public var entityCharacteristicsName: String?
    public var entityCharacteristicType: String = ""

    public var motionDetected: Bool?
    public var illuminanceInLux: Double?
    public var isDeviceOn: Bool?
    public var isContactOpen: Bool?
    public var isDoorLocked: Bool?
    public var stateOfCharge: Int?
    public var isHeaterActive: Bool?

    @Transient
    public var dataDescription: String {
        var data: [String] = []
        for type in EntityStorageItemType.allCases {
            switch type {
            case .motion:
                data.append("motionDetected: \(String(describing: motionDetected))")
            case .illuminance:
                data.append("illuminance: \(String(describing: illuminanceInLux))")
            case .isDeviceOn:
                data.append("isDeviceOn: \(String(describing: isDeviceOn))")
            case .isContactOpen:
                data.append("isContactOpen: \(String(describing: isContactOpen))")
            case .isDoorLocked:
                data.append("isDoorLocked: \(String(describing: isDoorLocked))")
            case .stateOfCharge:
                data.append("stateOfCharge: \(String(describing: stateOfCharge))")
            case .isHeaterActive:
                data.append("isHeaterActive: \(String(describing: isHeaterActive))")
            }
        }
        return "\(data.joined(separator: " - "))"
    }

    public init(timestamp: Date, entityPlaceId: PlaceId, entityName: String, entityCharacteristicsName: String?, entityCharacteristicType: String, motionDetected: Bool?, illuminanceInLux: Double?, isDeviceOn: Bool?, isContactOpen: Bool?, isDoorLocked: Bool?, stateOfCharge: Int?, isHeaterActive: Bool?) {
        self.timestamp = timestamp
        self.entityPlaceId = entityPlaceId
        self.entityServiceName = entityName
        self.entityCharacteristicsName = entityCharacteristicsName
        self.entityCharacteristicType = entityCharacteristicType
        self.motionDetected = motionDetected
        self.illuminanceInLux = illuminanceInLux
        self.isDeviceOn = isDeviceOn
        self.isContactOpen = isContactOpen
        self.isDoorLocked = isDoorLocked
        self.stateOfCharge = stateOfCharge
        self.isHeaterActive = isHeaterActive
    }
}
#endif
