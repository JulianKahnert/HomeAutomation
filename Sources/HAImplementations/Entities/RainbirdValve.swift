//
//  RainbirdValve.swift
//
//
//  Created by Julian Kahnert on 03.07.24.
//

import Foundation
import HAModels

public final class RainbirdValve: ValveDevice, @unchecked Sendable {
    public convenience init(query: EntityId.Query) {
        self.init(valveId: EntityId(query: query, characteristic: .valve))
    }
}
