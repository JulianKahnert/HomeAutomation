//
//  CharacteristicsType.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 18.11.24.
//

public enum CharacteristicsType: String, Sendable, Codable {
    case motionSensor, lightSensor, batterySensor, contactSensor
    case switcher, brightness, colorTemperature, color, valve
    case lock
    case heating
}
