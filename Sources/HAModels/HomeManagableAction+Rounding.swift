//
//  HomeManagableAction+Rounding.swift
//  HomeAutomation
//
//  Created by Claude Code on 15.11.25.
//

import Foundation

extension HomeManagableAction {
    /// Returns a copy of the action with float values rounded to 2 decimal places
    /// This prevents excessive HomeKit characteristic updates from minor float variations
    public func rounded() -> HomeManagableAction {
        switch self {
        case .setBrightness(let id, let value):
            return .setBrightness(id, value.rounded(toPlaces: 2))
        case .setColorTemperature(let id, let value):
            return .setColorTemperature(id, value.rounded(toPlaces: 2))
        case .setRGB(let id, let rgb):
            return .setRGB(id, rgb: rgb.rounded())
        default:
            return self // No rounding needed for other cases
        }
    }
}

extension Float {
    func rounded(toPlaces places: Int) -> Float {
        let divisor = pow(10.0, Float(places))
        return (self * divisor).rounded() / divisor
    }
}

extension RGB {
    func rounded() -> RGB {
        RGB(
            red: red.rounded(toPlaces: 2),
            green: green.rounded(toPlaces: 2),
            blue: blue.rounded(toPlaces: 2)
        )
    }
}
