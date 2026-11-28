//
//  MotionSensorDevice.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 12.02.25.
//

import Foundation
import Shared

open class MotionSensorDevice: Codable, @unchecked Sendable, Log {

    public let motionSensorId: EntityId
    public let lightSensorId: EntityId?
    public let batterySensorId: EntityId?

    public init(motionSensorId: EntityId, lightSensorId: EntityId?, batterySensorId: EntityId?) {
        self.motionSensorId = motionSensorId
        self.lightSensorId = lightSensorId
        self.batterySensorId = batterySensorId
    }

    public func motionDetectedState(with hm: HomeManagable) async throws -> Bool {
        let item = try await hm.getCurrentEntity(with: motionSensorId)
        return try item.motionDetected.get(with: log)
    }

    public func illuminanceState(with hm: HomeManagable) async throws -> Measurement<UnitIlluminance> {
        let lightSensorId = try lightSensorId.get(with: log)
        let item = try await hm.getCurrentEntity(with: lightSensorId)
        return try item.illuminance.get(with: log)
    }

}
