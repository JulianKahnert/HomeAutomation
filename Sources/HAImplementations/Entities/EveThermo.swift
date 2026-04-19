//
//  Untitled.swift
//  
//
//  Created by Julian Kahnert on 03.07.24.
//

import Foundation
import HAModels

public final class EveThermo: HeatSwitchDevice {
    public convenience init(query: EntityId.Query) {
        self.init(heatSwitchId: EntityId(query: query, characteristic: .heating))
    }
}
