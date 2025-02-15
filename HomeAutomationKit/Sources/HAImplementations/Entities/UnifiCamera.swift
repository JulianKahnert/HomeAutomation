//
//  UnifiCamera.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 12.07.24.
//

import Foundation
import HAModels

public final class UnifiCamera: MotionSensorDevice, @unchecked Sendable {
    public convenience init(query: EntityId.Query) {
        self.init(motionSensorId: EntityId(query: query, characteristic: .motionSensor),
                  lightSensorId: nil,
                  batterySensorId: nil)
    }
}
