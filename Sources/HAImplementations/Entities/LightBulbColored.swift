//
//  LightBulbColored.swift
//
//
//  Created by Julian Kahnert on 03.07.24.
//

import Foundation
import HAModels

public final class LightBulbColored: SwitchDevice, @unchecked Sendable {
    public convenience init(query: EntityId.Query) {
        self.init(switchId: EntityId(query: query, characteristic: .switcher),
                  brightnessId: EntityId(query: query, characteristic: .brightness),
                  colorTemperatureId: nil,
                  rgbId: EntityId(query: query, characteristic: .color))
    }
}
