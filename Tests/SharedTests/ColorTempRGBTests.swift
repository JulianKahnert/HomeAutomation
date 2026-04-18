//
//  ColorTempRGBTests.swift
//  HomeAutomation
//

import Foundation
import HAModels
import XCTest

final class ColorTempRGBTests: XCTestCase {

    // MARK: - RGB to HSV Conversion Tests

    func testHSVFromRGB_PureRed() {
        let rgb = RGB(red: 1.0, green: 0.0, blue: 0.0)
        let hsv = hsv(from: rgb)

        XCTAssertEqual(hsv.h, 0.0, accuracy: 1.0, "Pure red should have hue of 0°")
        XCTAssertEqual(hsv.s, 1.0, accuracy: 0.01, "Pure red should have full saturation")
        XCTAssertEqual(hsv.v, 1.0, accuracy: 0.01, "Pure red should have full value")
    }

    func testHSVFromRGB_PureGreen() {
        let rgb = RGB(red: 0.0, green: 1.0, blue: 0.0)
        let hsv = hsv(from: rgb)

        XCTAssertEqual(hsv.h, 120.0, accuracy: 1.0, "Pure green should have hue of 120°")
        XCTAssertEqual(hsv.s, 1.0, accuracy: 0.01, "Pure green should have full saturation")
        XCTAssertEqual(hsv.v, 1.0, accuracy: 0.01, "Pure green should have full value")
    }

    func testHSVFromRGB_PureBlue() {
        let rgb = RGB(red: 0.0, green: 0.0, blue: 1.0)
        let hsv = hsv(from: rgb)

        XCTAssertEqual(hsv.h, 240.0, accuracy: 1.0, "Pure blue should have hue of 240°")
        XCTAssertEqual(hsv.s, 1.0, accuracy: 0.01, "Pure blue should have full saturation")
        XCTAssertEqual(hsv.v, 1.0, accuracy: 0.01, "Pure blue should have full value")
    }

    func testHSVFromRGB_Yellow() {
        let rgb = RGB(red: 1.0, green: 1.0, blue: 0.0)
        let hsv = hsv(from: rgb)

        XCTAssertEqual(hsv.h, 60.0, accuracy: 1.0, "Yellow should have hue of 60°")
        XCTAssertEqual(hsv.s, 1.0, accuracy: 0.01, "Yellow should have full saturation")
        XCTAssertEqual(hsv.v, 1.0, accuracy: 0.01, "Yellow should have full value")
    }

    func testHSVFromRGB_Cyan() {
        let rgb = RGB(red: 0.0, green: 1.0, blue: 1.0)
        let hsv = hsv(from: rgb)

        XCTAssertEqual(hsv.h, 180.0, accuracy: 1.0, "Cyan should have hue of 180°")
        XCTAssertEqual(hsv.s, 1.0, accuracy: 0.01, "Cyan should have full saturation")
        XCTAssertEqual(hsv.v, 1.0, accuracy: 0.01, "Cyan should have full value")
    }

    func testHSVFromRGB_Magenta() {
        let rgb = RGB(red: 1.0, green: 0.0, blue: 1.0)
        let hsv = hsv(from: rgb)

        XCTAssertEqual(hsv.h, 300.0, accuracy: 1.0, "Magenta should have hue of 300°")
        XCTAssertEqual(hsv.s, 1.0, accuracy: 0.01, "Magenta should have full saturation")
        XCTAssertEqual(hsv.v, 1.0, accuracy: 0.01, "Magenta should have full value")
    }

    func testHSVFromRGB_White() {
        let rgb = RGB(red: 1.0, green: 1.0, blue: 1.0)
        let hsv = hsv(from: rgb)

        XCTAssertEqual(hsv.h, 0.0, accuracy: 1.0, "White should have hue of 0° (undefined)")
        XCTAssertEqual(hsv.s, 0.0, accuracy: 0.01, "White should have no saturation")
        XCTAssertEqual(hsv.v, 1.0, accuracy: 0.01, "White should have full value")
    }

    func testHSVFromRGB_Black() {
        let rgb = RGB(red: 0.0, green: 0.0, blue: 0.0)
        let hsv = hsv(from: rgb)

        XCTAssertEqual(hsv.h, 0.0, accuracy: 1.0, "Black should have hue of 0° (undefined)")
        XCTAssertEqual(hsv.s, 0.0, accuracy: 0.01, "Black should have no saturation")
        XCTAssertEqual(hsv.v, 0.0, accuracy: 0.01, "Black should have no value")
    }

    func testHSVFromRGB_Gray() {
        let rgb = RGB(red: 0.5, green: 0.5, blue: 0.5)
        let hsv = hsv(from: rgb)

        XCTAssertEqual(hsv.h, 0.0, accuracy: 1.0, "Gray should have hue of 0° (undefined)")
        XCTAssertEqual(hsv.s, 0.0, accuracy: 0.01, "Gray should have no saturation")
        XCTAssertEqual(hsv.v, 0.5, accuracy: 0.01, "Gray should have medium value")
    }

    // MARK: - HSV to RGB Conversion Tests

    func testRGBFromHSV_PureRed() {
        let rgb = rgb(h: 0.0, s: 1.0, v: 1.0)

        XCTAssertEqual(rgb.red, 1.0, accuracy: 0.01, "Pure red hue should produce red=1")
        XCTAssertEqual(rgb.green, 0.0, accuracy: 0.01, "Pure red hue should produce green=0")
        XCTAssertEqual(rgb.blue, 0.0, accuracy: 0.01, "Pure red hue should produce blue=0")
    }

    func testRGBFromHSV_PureGreen() {
        let rgb = rgb(h: 120.0 / 360.0, s: 1.0, v: 1.0)

        XCTAssertEqual(rgb.red, 0.0, accuracy: 0.01, "Pure green hue should produce red=0")
        XCTAssertEqual(rgb.green, 1.0, accuracy: 0.01, "Pure green hue should produce green=1")
        XCTAssertEqual(rgb.blue, 0.0, accuracy: 0.01, "Pure green hue should produce blue=0")
    }

    func testRGBFromHSV_PureBlue() {
        let rgb = rgb(h: 240.0 / 360.0, s: 1.0, v: 1.0)

        XCTAssertEqual(rgb.red, 0.0, accuracy: 0.01, "Pure blue hue should produce red=0")
        XCTAssertEqual(rgb.green, 0.0, accuracy: 0.01, "Pure blue hue should produce green=0")
        XCTAssertEqual(rgb.blue, 1.0, accuracy: 0.01, "Pure blue hue should produce blue=1")
    }

    func testRGBFromHSV_Grayscale() {
        let rgb = rgb(h: 0.0, s: 0.0, v: 0.5)

        XCTAssertEqual(rgb.red, 0.5, accuracy: 0.01, "Grayscale should have equal RGB components")
        XCTAssertEqual(rgb.green, 0.5, accuracy: 0.01, "Grayscale should have equal RGB components")
        XCTAssertEqual(rgb.blue, 0.5, accuracy: 0.01, "Grayscale should have equal RGB components")
    }

    // MARK: - Round-trip Tests

    func testRGBToHSVAndBack_PureColors() {
        let testColors: [(String, RGB)] = [
            ("Red", RGB(red: 1.0, green: 0.0, blue: 0.0)),
            ("Green", RGB(red: 0.0, green: 1.0, blue: 0.0)),
            ("Blue", RGB(red: 0.0, green: 0.0, blue: 1.0)),
            ("Yellow", RGB(red: 1.0, green: 1.0, blue: 0.0)),
            ("Cyan", RGB(red: 0.0, green: 1.0, blue: 1.0)),
            ("Magenta", RGB(red: 1.0, green: 0.0, blue: 1.0))
        ]

        for (name, original) in testColors {
            let hsv = HAModels.hsv(from: original)
            let restored = HAModels.rgb(h: hsv.h / 360.0, s: hsv.s, v: hsv.v)

            XCTAssertEqual(restored.red, original.red, accuracy: 0.01, "\(name): Red component should match")
            XCTAssertEqual(restored.green, original.green, accuracy: 0.01, "\(name): Green component should match")
            XCTAssertEqual(restored.blue, original.blue, accuracy: 0.01, "\(name): Blue component should match")
        }
    }

    // MARK: - Color Temperature Tests

    func testColorTemperatureNormalized_Warm() {
        let rgb = componentsForColorTemperature(normalized: 0.0) // 2000K (500 mired)

        XCTAssertGreaterThan(rgb.red, rgb.blue, "Warm light should have more red than blue")
        XCTAssertGreaterThan(rgb.red, 0.9, "Warm light should have a high red component")
        XCTAssertLessThan(rgb.blue, 0.2, "Warm light should have a very low blue component")
    }

    func testColorTemperatureNormalized_Cool() {
        let rgb = componentsForColorTemperature(normalized: 1.0) // ≈ 6494K (154 mired)

        // 6500K approximates daylight white: high red AND high blue.
        XCTAssertGreaterThan(rgb.red, 0.9, "Cool daylight should still have a high red component")
        XCTAssertGreaterThan(rgb.blue, 0.9, "Cool daylight should have a high blue component")
        XCTAssertGreaterThan(rgb.green, 0.9, "Cool daylight should have a high green component")
    }

    /// Guards that the cool end of the normalized range reaches true daylight
    /// (low-saturation white), keeping the RGB path visually aligned with the
    /// native HomeKit color-temperature characteristic.
    func testColorTemperatureNormalized_RangeReachesDaylight() {
        let cool = componentsForColorTemperature(normalized: 1.0)

        // Saturation should be very low at true daylight — nearly neutral white.
        let hsv = HAModels.hsv(from: cool)
        XCTAssertLessThan(hsv.s, 0.15, "Cool end should produce near-neutral white, got saturation \(hsv.s)")
    }

    /// The normalized scale runs linearly in *mired*, matching the native
    /// HomeKit color-temperature characteristic. This keeps visual parity
    /// between RGB and native bulbs when the same normalized input is used.
    func testColorTemperatureNormalized_MiredLinearMapping() {
        // mired at value = 0.5 is the midpoint of 154…500, i.e. 327 → ≈ 3058K.
        let midpoint = componentsForColorTemperature(normalized: 0.5)
        let expected = componentsForColorTemperature(temperatureInKelvin: 1_000_000 / 327)

        XCTAssertEqual(midpoint.red, expected.red, accuracy: 0.01)
        XCTAssertEqual(midpoint.green, expected.green, accuracy: 0.01)
        XCTAssertEqual(midpoint.blue, expected.blue, accuracy: 0.01)
    }

    func testColorTemperatureNormalized_MonotonicBlueIncrease() {
        // Moving from warm (0) to cool (1), blue should increase monotonically.
        let samples = stride(from: Float(0), through: Float(1), by: 0.1).map {
            componentsForColorTemperature(normalized: $0).blue
        }
        for (prev, next) in zip(samples, samples.dropFirst()) {
            XCTAssertLessThanOrEqual(prev, next + 0.0001, "Blue component must not decrease as color temperature rises")
        }
    }

    func testColorTemperatureKelvin_2700K() {
        let rgb = componentsForColorTemperature(temperatureInKelvin: 2700)

        // 2700K is typical warm white - should be yellowish
        XCTAssertGreaterThan(rgb.red, 0.9, "2700K should have high red")
        XCTAssertGreaterThan(rgb.green, 0.6, "2700K should have medium green")
        XCTAssertLessThan(rgb.blue, 0.5, "2700K should have low blue")
    }

    func testColorTemperatureKelvin_6500K() {
        let rgb = componentsForColorTemperature(temperatureInKelvin: 6500)

        // 6500K is daylight - should be bluish white
        XCTAssertGreaterThan(rgb.blue, 0.9, "6500K should have high blue")
    }
}
