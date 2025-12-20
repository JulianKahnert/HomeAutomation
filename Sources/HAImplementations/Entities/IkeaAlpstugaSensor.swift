//
//  IkeaAlpstugaSensor.swift
//  
//
//  Created by Julian Kahnert on 03.07.24.
//

import Foundation
import HAModels

public final class IkeaAlpstugaSensor: AirSensorDevice, @unchecked Sendable {
    public convenience init(query: EntityId.Query) {
        self.init(temperatureSensorId: EntityId(query: query, characteristic: .temperatureSensor),
                  relativeHumiditySensorId: EntityId(query: query, characteristic: .relativeHumiditySensor),
                  carbonDioxideSensorId: EntityId(query: query, characteristic: .carbonDioxideSensorId),
                  pmDensitySensorId: EntityId(query: query, characteristic: .pmDensitySensor),
                  batterySensorId: nil,
                  airQualitySensorId: EntityId(query: query, characteristic: .airQualitySensor))
    }
}
