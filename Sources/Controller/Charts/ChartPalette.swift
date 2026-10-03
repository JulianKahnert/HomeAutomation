//
//  ChartPalette.swift
//  Controller
//

import HAModels
import SwiftUI

/// Chart colors follow the device type, never the series order, so a lamp is green in every chart.
enum ChartPalette {
    static func color(for type: CharacteristicsType) -> Color {
        switch type {
        case .switcher, .brightness, .colorTemperature, .color:
            return .green
        case .motionSensor:
            return .blue
        case .contactSensor:
            return .orange
        case .lightSensor:
            return .indigo
        case .carbonDioxideSensorId:
            return .teal
        default:
            return .gray
        }
    }

    static let night = Color.gray.opacity(0.15)
}
