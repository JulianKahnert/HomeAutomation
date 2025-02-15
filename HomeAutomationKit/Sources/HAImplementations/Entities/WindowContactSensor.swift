//
//  WindowContactSensor.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 20.07.24.
//

import Foundation
import HAModels

public final class WindowContactSensor: ContactSensorDevice, @unchecked Sendable {
    public convenience init(query: EntityId.Query) {
        self.init(contactSensorId: EntityId(query: query, characteristic: .contactSensor),
                  batterySensorId: EntityId(query: query, characteristic: .batterySensor))
    }
}
