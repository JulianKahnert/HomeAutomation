//
//  HeatingPalette.swift
//  ControllerFeatures
//
//  One colour rule for Δ: blue too cold, grey in the comfort band, orange too warm
//

import HAModels
import SwiftUI

enum HeatingPalette {
    /// Comfort band of ±0.5 K (glossary: Δ).
    static let comfortBand = 0.5
    /// Bars run off the end beyond ±3 K.
    static let barScale = 3.0

    enum Band: Equatable, Sendable {
        case tooCold, ok, tooWarm
    }

    static func band(forDelta delta: Double) -> Band {
        if delta < -comfortBand { return .tooCold }
        if delta > comfortBand { return .tooWarm }
        return .ok
    }

    static func color(_ band: Band, scheme: ColorScheme) -> Color {
        switch band {
        case .tooCold: .blue
        case .ok: .gray
        // Dark mode: a peach tone instead of a brown orange; tune against real data.
        case .tooWarm: scheme == .dark ? Color(red: 1.0, green: 0.62, blue: 0.4) : .orange
        }
    }

    static func color(forDelta delta: Double, scheme: ColorScheme) -> Color {
        color(band(forDelta: delta), scheme: scheme)
    }

    /// The soft grey of the actual-value line.
    static func istLine(scheme: ColorScheme) -> Color {
        Color(white: scheme == .dark ? 0.68 : 0.38)
    }

    static let valveColors: [Color] = [.green, .mint, .teal]

    static func card(_ scheme: ColorScheme) -> Color {
        #if canImport(UIKit)
        Color(.secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}
