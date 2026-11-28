//
//  ChartLabel.swift
//  Controller
//

import Foundation

/// The names of the plotted values. A chart exposes them to VoiceOver, so they are localized.
enum ChartLabel {
    static let time = String(localized: "Time", bundle: .module)
    static let start = String(localized: "Start", bundle: .module)
    static let end = String(localized: "End", bundle: .module)
    static let day = String(localized: "Day", bundle: .module)
    static let series = String(localized: "Series", bundle: .module)
    static let lane = String(localized: "Lane", bundle: .module)
    static let kind = String(localized: "Kind", bundle: .module)
    static let threshold = String(localized: "Threshold", bundle: .module)
    static let actual = String(localized: "Actual", bundle: .module)
    static let plan = String(localized: "Plan", bundle: .module)
    static let deviation = String(localized: "Deviation", bundle: .module)
    static let valve = String(localized: "Valve", bundle: .module)
    static let room = String(localized: "Room", bundle: .module)
    /// The deviation from the plan, in kelvin.
    static let delta = "Δ"
}
