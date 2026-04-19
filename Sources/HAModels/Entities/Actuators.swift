//
//  Actuators.swift
//  
//
//  Created by Julian Kahnert on 01.07.24.
//

import Foundation

public final class HeatSwitch: HeatSwitchDevice {
    public convenience init(query: EntityId.Query) {
        self.init(heatSwitchId: EntityId(query: query, characteristic: .heating))
    }
}
