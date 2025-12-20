//
//  AirSensorDevice.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 13.02.25.
//

import Foundation
import Shared

open class AirSensorDevice: Codable, @unchecked Sendable, Validatable, Log {
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

    public func validate(with hm: any EntityValidator) async throws {

        try await hm.findEntity(temperatureSensorId)
        try await hm.findEntity(relativeHumiditySensorId)

        if let carbonDioxideSensorId {
            do {
                try await hm.findEntity(carbonDioxideSensorId)
            } catch {
                log.warning("Failed to get battery sensor for \(carbonDioxideSensorId)")
            }
        }

        if let pmDensitySensorId {
            do {
                try await hm.findEntity(pmDensitySensorId)
            } catch {
                log.warning("Failed to get battery sensor for \(pmDensitySensorId)")
            }
        }

        if let batterySensorId {
            do {
                try await hm.findEntity(batterySensorId)
            } catch {
                log.warning("Failed to get battery sensor for \(batterySensorId)")
            }
        }

        if let airQualitySensorId {
            do {
                try await hm.findEntity(airQualitySensorId)
            } catch {
                log.warning("Failed to get battery sensor for \(airQualitySensorId)")
            }
        }
    }
}
