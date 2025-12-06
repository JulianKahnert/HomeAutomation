//
//  LightBulbDimmable.swift
//
//
//  Created by Julian Kahnert on 03.07.24.
//

import Foundation
import HAModels

public final class LightBulbDimmable: SwitchDevice, @unchecked Sendable {
    public convenience init(query: EntityId.Query, skipColorTemperature: Bool = false) {
        self.init(switchId: EntityId(query: query, characteristic: .switcher),
                  brightnessId: EntityId(query: query, characteristic: .brightness),
                  colorTemperatureId: nil,
                  rgbId: nil,
                  skipColorTemperature: skipColorTemperature)
    }
}
