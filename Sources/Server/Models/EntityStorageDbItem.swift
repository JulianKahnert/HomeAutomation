//
//  EntityStorageDbItem.swift
//  HomeAutomationServer
//
//  Created by Julian Kahnert on 06.02.25.
//

import Fluent
import Foundation
import HAModels

/// Property wrappers interact poorly with `Sendable` checking, causing a warning for the `@ID` property
/// It is recommended you write your model with sendability checking on and then suppress the warning
/// afterwards with `@unchecked Sendable`.
final class EntityStorageDbItem: Model, @unchecked Sendable {
    static let schema = "entityItems"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "timestamp")
    var timestamp: Date

    @Field(key: "entityPlaceId")
    var entityPlaceId: String

    @Field(key: "entityServiceName")
    var entityServiceName: String

    @Field(key: "entityCharacteristicsName")
    var entityCharacteristicsName: String?

    @Field(key: "entityCharacteristicType")
    var entityCharacteristicType: String

    @Field(key: "motionDetected")
    var motionDetected: Bool?

    @Field(key: "illuminanceInLux")
    var illuminanceInLux: Double?

    @Field(key: "isDeviceOn")
    var isDeviceOn: Bool?

    @Field(key: "isContactOpen")
    var isContactOpen: Bool?

    @Field(key: "isDoorLocked")
    var isDoorLocked: Bool?

    @Field(key: "stateOfCharge")
    var stateOfCharge: Int?

    @Field(key: "isHeaterActive")
    var isHeaterActive: Bool?

    @Field(key: "brightness")
    var brightness: Int?

    @Field(key: "colorTemperature")
    var colorTemperature: Float?

    @Field(key: "colorRed")
    var colorRed: Float?

    @Field(key: "colorGreen")
    var colorGreen: Float?

    @Field(key: "colorBlue")
    var colorBlue: Float?

    @Field(key: "temperatureInC")
    var temperatureInC: Double?

    @Field(key: "relativeHumidity")
    var relativeHumidity: Double?

    @Field(key: "carbonDioxideSensorId")
    var carbonDioxideSensorId: Int?

    @Field(key: "pmDensity")
    var pmDensity: Double?

    @Field(key: "airQuality")
    var airQuality: Int?

    @Field(key: "valveOpen")
    var valveOpen: Bool?

    init() { }

    init(timestamp: Date, entityPlaceId: String, entityServiceName: String, entityCharacteristicsName: String? = nil, entityCharacteristicType: String, motionDetected: Bool? = nil, illuminanceInLux: Double? = nil, isDeviceOn: Bool? = nil, isContactOpen: Bool? = nil, isDoorLocked: Bool? = nil, stateOfCharge: Int? = nil, isHeaterActive: Bool? = nil, brightness: Int? = nil, colorTemperature: Float? = nil, colorRed: Float? = nil, colorGreen: Float? = nil, colorBlue: Float? = nil, temperatureInC: Double? = nil, relativeHumidity: Double? = nil, carbonDioxideSensorId: Int? = nil, pmDensity: Double? = nil, airQuality: Int? = nil, valveOpen: Bool? = nil) {
        self.timestamp = timestamp
        self.entityPlaceId = entityPlaceId
        self.entityServiceName = entityServiceName
        self.entityCharacteristicsName = entityCharacteristicsName
        self.entityCharacteristicType = entityCharacteristicType
        self.motionDetected = motionDetected
        self.illuminanceInLux = illuminanceInLux
        self.isDeviceOn = isDeviceOn
        self.isContactOpen = isContactOpen
        self.isDoorLocked = isDoorLocked
        self.stateOfCharge = stateOfCharge
        self.isHeaterActive = isHeaterActive
        self.brightness = brightness
        self.colorTemperature = colorTemperature
        self.colorRed = colorRed
        self.colorGreen = colorGreen
        self.colorBlue = colorBlue
        self.temperatureInC = temperatureInC
        self.relativeHumidity = relativeHumidity
        self.carbonDioxideSensorId = carbonDioxideSensorId
        self.pmDensity = pmDensity
        self.airQuality = airQuality
        self.valveOpen = valveOpen
    }
}
