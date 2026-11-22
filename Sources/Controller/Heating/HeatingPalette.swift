//
//  HeatingPalette.swift
//  ControllerFeatures
//
//  One colour rule for Δ: blue too cold, grey in the comfort band, orange too warm
//

import HAModels
import SwiftUI

enum HeatingPalette {
    /// Bars run off the end beyond ±3 K.
    static let barScale = 3.0

    static func color(_ comfort: HeatingComfort, scheme: ColorScheme) -> Color {
        switch comfort {
        case .tooCold: return .blue
        case .ok: return .gray
        // Dark mode: a peach tone instead of a brown orange; tune against real data.
        case .tooWarm: return scheme == .dark ? Color(red: 1.0, green: 0.62, blue: 0.4) : .orange
        }
    }

    static func color(forDelta delta: Double, scheme: ColorScheme) -> Color {
        color(HeatingComfort(delta: delta), scheme: scheme)
    }

    /// The soft grey of the actual-value line.
    static func istLine(scheme: ColorScheme) -> Color {
        Color(white: scheme == .dark ? 0.68 : 0.38)
    }

    /// The neutral grey of a selection: the pill on a room name, the range segment.
    static let softFill = Color.secondary.opacity(0.14)

    /// The selected segment of the range switch: a step above the soft track.
    static let selectedSegment = Color.secondary.opacity(0.24)

    /// The filled area of a radiator's valve chart: green, the first radiator the strongest.
    static func valveFill(radiator: Int) -> Color {
        Color.green.opacity(radiator == 0 ? 0.35 : 0.2)
    }

    static var card: Color {
        #if canImport(UIKit)
        Color(.secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}
