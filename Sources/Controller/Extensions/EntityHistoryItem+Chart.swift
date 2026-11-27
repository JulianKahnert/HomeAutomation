//
//  EntityHistoryItem+Chart.swift
//  Controller
//
//  Chart visualization extensions for EntityHistoryItem
//

import Foundation
import HAModels
import SwiftUI

extension EntityHistoryItem {
    /// The colour of a colour value (the text "r g b" with components 0...1).
    private var rgb: RGB? {
        guard descriptor?.display == .color, case .text(let text) = value else { return nil }
        let parts = text.split(separator: " ").compactMap { Float($0) }
        guard parts.count == 3 else { return nil }
        return RGB(red: parts[0], green: parts[1], blue: parts[2])
    }

    /// Returns a SwiftUI Color from the colour value if available
    public var color: Color? {
        rgb.map { Color(red: Double($0.red), green: Double($0.green), blue: Double($0.blue)) }
    }

    /// The hue (color tone) in degrees (0-360°) of the colour value
    private var hue: Double? {
        rgb.map { Double($0.hue) }
    }

    /// The on/open/detected state of boolean values, `nil` for measurements.
    var stateValue: Bool? {
        guard case .bool(let bool) = value else { return nil }
        return bool
    }

    /// The value as a number for charts, from the value and its descriptor: a number as is, a Bool as 1 or 0,
    /// a colour as its hue, `nil` for a text that is no colour. A kind without a descriptor charts its raw number.
    public var primaryValue: Double? {
        switch value {
        case .bool(let bool):
            return bool ? 1.0 : 0.0
        case .number(let number):
            return number
        case .text:
            return descriptor?.display == .color ? hue : nil
        case nil:
            return nil
        }
    }
}
