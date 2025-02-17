//
//  ConfigDTO.swift
//  HomeAutomationServer
//
//  Created by Julian Kahnert on 14.02.25.
//

import HAModels

public struct ConfigDTO: Codable, Sendable {
    public let location: Location
    public let automations: [AnyAutomation]

    public init(location: Location, automations: [AnyAutomation]) {
        self.location = location
        self.automations = automations
    }
}
