//
//  Radiator.swift
//  HAImplementations
//

import Foundation
import HAModels

/// A thermostat that shows up as heating switch plus target temperature, e.g. the Eve Thermo.
public final class Radiator: RadiatorDevice, @unchecked Sendable {
    public convenience init(query: EntityId.Query) {
        self.init(heatingId: EntityId(query: query, characteristic: .heating),
                  targetTemperatureId: EntityId(query: query, characteristic: .targetTemperature))
    }
}
