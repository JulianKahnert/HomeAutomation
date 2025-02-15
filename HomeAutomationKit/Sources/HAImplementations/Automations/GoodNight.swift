//
//  TurnOff.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 20.07.24.
//

import Foundation
import HAModels

public struct GoodNight: Automatable {
    public let name: String
    public let time: Time
    public let motionSensors: [MotionSensorDevice]
    public let motionWait: Duration
    public var triggerEntityIds: Set<EntityId> {
        []
    }

    public init(_ name: String, at time: Time, motionSensors: [MotionSensorDevice], motionWait: Duration) {
        self.name = name
        self.time = time
        self.motionSensors = motionSensors
        self.motionWait = motionWait
    }

    public func shouldTrigger(with event: HomeEvent, using hm: HomeManagable) async throws -> Bool {
        return time.isEqual(event)
    }

    public func execute(using hm: HomeManagable) async throws {
        log.debug("Trigger good night scene to turn off devices + close locks")

        try await noMotionOrWait(using: hm)

        await hm.trigger(scene: UpdateScenes.sceneNameGoodNight)
    }

    private func noMotionOrWait(using hm: HomeManagable) async throws {
        let motionSensorIds = motionSensors.map(\.motionSensorId)

        var waitCount = 0
        while waitCount <= 4 {

            var shouldWait = false
            for motionSensorId in motionSensorIds {

                // found currently some motion
                let currentMotionEntry = try? await hm.getCurrentEntity(with: motionSensorId)
                if let isCurrentlyMotion = currentMotionEntry?.motionDetected,
                   isCurrentlyMotion {
                    shouldWait = true
                }

                // found motion in the last x minutes
                let lastMotionEntry = try? await hm.getPreviousEntity(with: motionSensorId)
                if let lastMotionEntry,
                   lastMotionEntry.timestamp < Date().addingTimeInterval(-1 * motionWait.timeInterval) {
                    shouldWait = true
                }
            }

            if shouldWait {
                try await Task.sleep(for: motionWait)
            }
            waitCount += 1
        }
    }
}
