//
//  AirSensorDevice.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 13.02.25.
//

import Foundation
import Shared

open class AirSensorDevice: Codable, @unchecked Sendable, Log {
    /// Current Temperature
    public let temperatureSensorId: EntityId

    /// Current Relative Humidity
    public let relativeHumiditySensorId: EntityId

    /// Carbon dioxide Level
    public let carbonDioxideSensorId: EntityId?

    /// PM2.5 Density
    public let pmDensitySensorId: EntityId?

    /// Carbon dioxide Level
    public let batterySensorId: EntityId?

    /// Air Quality
    public let airQualitySensorId: EntityId?

    public init(temperatureSensorId: EntityId, relativeHumiditySensorId: EntityId, carbonDioxideSensorId: EntityId?, pmDensitySensorId: EntityId?, batterySensorId: EntityId?, airQualitySensorId: EntityId?) {
        self.temperatureSensorId = temperatureSensorId
        self.relativeHumiditySensorId = relativeHumiditySensorId
        self.carbonDioxideSensorId = carbonDioxideSensorId
        self.pmDensitySensorId = pmDensitySensorId
        self.batterySensorId = batterySensorId
        self.airQualitySensorId = airQualitySensorId
    }

}
