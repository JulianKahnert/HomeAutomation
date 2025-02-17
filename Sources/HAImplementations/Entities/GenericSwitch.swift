//
//  GenericSwitch.swift
//
//
//  Created by Julian Kahnert on 03.07.24.
//

import Foundation
import HAModels

public final class GenericSwitch: SwitchDevice {
    public convenience init(query: EntityId.Query) {
        self.init(switchId: EntityId(query: query, characteristic: .switcher),
                  brightnessId: nil,
                  colorTemperatureId: nil,
                  rgbId: nil)
    }
}
