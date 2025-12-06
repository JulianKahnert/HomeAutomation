//
//  IkeaLightBulbColored.swift
//
//
//  Created by Julian Kahnert on 03.07.24.
//

import Foundation
import HAModels

public final class IkeaLightBulbColored: SwitchDevice, @unchecked Sendable {
    public convenience init(query: EntityId.Query, skipColorTemperature: Bool = false) {
        self.init(switchId: EntityId(query: query, characteristic: .switcher),
                  brightnessId: EntityId(query: query, characteristic: .brightness),
                  // IKEA light bulbs do not expose a color temperature property, so we need to use the RGB value for setting the temperature
                  colorTemperatureId: nil,
                  rgbId: EntityId(query: query, characteristic: .color),
                  skipColorTemperature: skipColorTemperature)
    }
}
