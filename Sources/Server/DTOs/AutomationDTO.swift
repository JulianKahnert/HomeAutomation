//
//  ConfigDTO.swift
//  HomeAutomationServer
//
//  Created by Julian Kahnert on 14.02.25.
//

import Vapor

struct AutomationDTO: Content {
    let name: String
    let isActive: Bool
    let isRunning: Bool
}
