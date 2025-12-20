//
//  MotionSensorDevice.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 12.02.25.
//

import Foundation
import Shared

open class MotionSensorDevice: Codable, @unchecked Sendable, Validatable, Log {

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

    public func getStateOfCharge(with hm: HomeManagable) async throws -> Int {
        let batterySensorId = try batterySensorId.get(with: log)
        let item = try await hm.getCurrentEntity(with: batterySensorId)
        return try item.stateOfCharge.get(with: log)
    }

    public func validate(with hm: any EntityValidator) async throws {
        try await hm.findEntity(motionSensorId)
        if let lightSensorId {
            try await hm.findEntity(lightSensorId)
        }
        if let batterySensorId {
            do {
                try await hm.findEntity(batterySensorId)
            } catch {
                log.warning("Failed to get battery sensor for \(batterySensorId)")
            }
        }
    }
}
