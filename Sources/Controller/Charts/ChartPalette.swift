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

    /// Times for a day or less, weekdays beyond that; a week of "00:00" labels says nothing.
    static func axisFormat(for domain: ClosedRange<Date>) -> Date.FormatStyle {
        domain.upperBound.timeIntervalSince(domain.lowerBound) > 86_400 * 1.5
            ? .dateTime.weekday(.abbreviated)
            : .dateTime.hour().minute()
    }
}
