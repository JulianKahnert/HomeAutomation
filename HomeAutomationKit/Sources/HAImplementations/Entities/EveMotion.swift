//
//  Untitled.swift
//  
//
//  Created by Julian Kahnert on 03.07.24.
//

import Foundation
import HAModels

public final class EveMotion: MotionSensorDevice, @unchecked Sendable {
    public convenience init(query: EntityId.Query) {
        self.init(motionSensorId: EntityId(query: query, characteristic: .motionSensor),
                  lightSensorId: EntityId(query: query, characteristic: .lightSensor),
                  batterySensorId: EntityId(query: query, characteristic: .batterySensor))
    }
}
