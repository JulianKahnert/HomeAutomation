//
//  ColorTempRGB.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 28.07.24.
//

import Foundation

public struct RGB: Sendable, Codable {
    let red: Float
    let green: Float
    let blue: Float
}

public func componentsForColorTemperature(normalzied value: Float) -> RGB {
    let range: ClosedRange<Float> = 2000...4000
    let kelvin = (range.upperBound - range.lowerBound) * value + range.lowerBound

    return componentsForColorTemperature(temperatureInKelvin: kelvin)
}

/// Algorithm taken from Tanner Helland's post: http://www.tannerhelland.com/4435/convert-temperature-rgb-algorithm-code/
///
/// Source: https://github.com/davidf2281/ColorTempToRGB
public func componentsForColorTemperature(temperatureInKelvin: Float) -> RGB {
    let percentKelvin = temperatureInKelvin / 100
    let red, green, blue: Float

    red = clamp(percentKelvin <= 66 ? 255 : (329.698727446 * pow(percentKelvin - 60, -0.1332047592)))
    green = clamp(percentKelvin <= 66 ? (99.4708025861 * log(percentKelvin) - 161.1195681661) : 288.1221695283 * pow(percentKelvin - 60, -0.0755148492))
    blue = clamp(percentKelvin >= 66 ? 255 : (percentKelvin <= 19 ? 0 : 138.5177312231 * log(percentKelvin - 10) - 305.0447927307))

    return RGB(red: red / 255, green: green / 255, blue: blue / 255)

    func clamp(_ value: Float) -> Float {
        return value > 255 ? 255 : (value < 0 ? 0 : value)
    }
}

public func hsv(from rgb: RGB) -> (h: Float, s: Float, v: Float) {
    let r = rgb.red
    let g = rgb.green
    let b = rgb.blue

    let min = r < g ? (r < b ? r : b) : (g < b ? g : b)
    let max = r > g ? (r > b ? r : b) : (g > b ? g : b)

    let v = max
    let delta = max - min

    guard delta > 0.00001 else { return (h: 0, s: 0, v: max) }
    guard max > 0 else { return (h: -1, s: 0, v: v) } // Undefined, achromatic grey
    let s = delta / max

    let hue: (Float, Float) -> Float = { max, delta -> Float in
        if r == max { return (g - b) / delta } // between yellow & magenta
        else if g == max { return 2 + (b - r) / delta } // between cyan & yellow
        else { return 4 + (r - g) / delta } // between magenta & cyan
    }

    let h = hue(max, delta) * 60 // In degrees

    return (h: (h < 0 ? h + 360 : h), s: s, v: v)
}
