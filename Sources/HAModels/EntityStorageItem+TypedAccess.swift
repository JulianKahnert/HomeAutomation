//
//  EntityStorageItem+TypedAccess.swift
//  HAModels
//

import Foundation

/// The typed view of the one generic value. Nothing here is stored: every accessor reads ``EntityStorageItem/kind``
/// and ``EntityStorageItem/value`` and answers `nil` when the item carries another kind. A new value kind needs
/// no accessor; automations that want one for it add a line here.
public extension EntityStorageItem {
    /// Motion detection state (true if motion detected)
    var motionDetected: Bool? { bool(.motionSensor) }

    /// Light level measurement in lux
    var illuminance: Measurement<UnitIlluminance>? { number(.lightSensor).map { Measurement(value: $0, unit: .lux) } }

    /// Device power state (true if on, false if off)
    var isDeviceOn: Bool? { bool(.switcher) }

    /// Light brightness level (0-100)
    var brightness: Int? { int(.brightness) }

    /// Color temperature normalized to 0...1 (warm...cold), normalized from HomeKit's mired value using the device's min/max
    var colorTemperature: Float? { number(.colorTemperature).map(Float.init) }

    /// RGB color value
    var color: RGB? {
        guard case .text(let text)? = value(of: .color) else { return nil }
        let parts = text.split(separator: " ").compactMap { Float($0) }
        return parts.count == 3 ? RGB(red: parts[0], green: parts[1], blue: parts[2]) : nil
    }

    /// Contact sensor state (true if open, false if closed)
    var isContactOpen: Bool? { bool(.contactSensor) }

    /// Door lock state (true if locked, false if unlocked)
    var isDoorLocked: Bool? { bool(.lock) }

    /// Battery state of charge percentage (0-100)
    var stateOfCharge: Int? { int(.batterySensor) }

    /// Heater active state (true if heating)
    var isHeaterActive: Bool? { bool(.heating) }

    /// Temperature measurement in Celsius
    var temperatureInC: Measurement<UnitTemperature>? { number(.temperatureSensor).map { Measurement(value: $0, unit: .celsius) } }

    /// Relative humidity percentage (0-100)
    var relativeHumidity: Double? { number(.relativeHumiditySensor) }

    /// Carbon dioxide level in ppm
    var carbonDioxideSensorId: Int? { int(.carbonDioxideSensorId) }

    /// Particulate matter density (PM2.5/PM10)
    var pmDensity: Double? { number(.pmDensitySensor) }

    /// Air quality index
    var airQuality: Int? { int(.airQualitySensor) }

    /// Valve open state (true if open)
    var valveOpen: Bool? { bool(.valve) }

    /// Thermostat target temperature in Celsius
    var targetTemperatureInC: Double? { number(.targetTemperature) }

    /// Thermostat target mode
    var heatingMode: HeatingMode? { int(.heatingMode).flatMap(HeatingMode.init(rawValue:)) }

    /// Valve opening in percent (0-100), Eve custom characteristic
    var valvePositionPercent: Int? { int(.valvePosition) }

    /// Thermostat temperature offset in Celsius, already included in the temperature it reports
    var temperatureCalibrationInC: Double? { number(.temperatureCalibration) }
}

private extension EntityStorageItem {
    func bool(_ type: CharacteristicsType) -> Bool? {
        if case .bool(let bool)? = value(of: type) { bool } else { nil }
    }

    func number(_ type: CharacteristicsType) -> Double? {
        if case .number(let number)? = value(of: type) { number } else { nil }
    }

    func int(_ type: CharacteristicsType) -> Int? {
        number(type).flatMap { Int(exactly: $0) }
    }
}

/// The typed creators for tests, fixtures and the adapter. The item keeps the first value that is set: an item
/// carries one value, so a caller passes one.
public extension EntityStorageItem {
    init(
        entityId: EntityId,
        timestamp: Date = Date(),
        motionDetected: Bool? = nil,
        illuminance: Measurement<UnitIlluminance>? = nil,
        isDeviceOn: Bool? = nil,
        brightness: Int? = nil,
        colorTemperature: Float? = nil,
        color: RGB? = nil,
        isContactOpen: Bool? = nil,
        isDoorLocked: Bool? = nil,
        stateOfCharge: Int? = nil,
        isHeaterActive: Bool? = nil,
        temperatureInC: Measurement<UnitTemperature>? = nil,
        relativeHumidity: Double? = nil,
        carbonDioxideSensorId: Int? = nil,
        pmDensity: Double? = nil,
        airQuality: Int? = nil,
        valveOpen: Bool? = nil,
        targetTemperatureInC: Double? = nil,
        heatingMode: HeatingMode? = nil,
        valvePositionPercent: Int? = nil,
        temperatureCalibrationInC: Double? = nil,
        origin: Origin = .homekit,
        lastReport: Date? = nil
    ) {
        let candidates: [(CharacteristicsType, Value?)] = [
            (.motionSensor, motionDetected.map { .bool($0) }),
            (.lightSensor, illuminance.map { .number($0.converted(to: .lux).value) }),
            (.switcher, isDeviceOn.map { .bool($0) }),
            (.brightness, brightness.map { .number(Double($0)) }),
            (.colorTemperature, colorTemperature.map { .number(Double($0)) }),
            (.color, color.map { .text("\($0.red) \($0.green) \($0.blue)") }),
            (.contactSensor, isContactOpen.map { .bool($0) }),
            (.lock, isDoorLocked.map { .bool($0) }),
            (.batterySensor, stateOfCharge.map { .number(Double($0)) }),
            (.heating, isHeaterActive.map { .bool($0) }),
            (.temperatureSensor, temperatureInC.map { .number($0.converted(to: .celsius).value) }),
            (.relativeHumiditySensor, relativeHumidity.map { .number($0) }),
            (.carbonDioxideSensorId, carbonDioxideSensorId.map { .number(Double($0)) }),
            (.pmDensitySensor, pmDensity.map { .number($0) }),
            (.airQualitySensor, airQuality.map { .number(Double($0)) }),
            (.valve, valveOpen.map { .bool($0) }),
            (.targetTemperature, targetTemperatureInC.map { .number($0) }),
            (.heatingMode, heatingMode.map { .number(Double($0.rawValue)) }),
            (.valvePosition, valvePositionPercent.map { .number(Double($0)) }),
            (.temperatureCalibration, temperatureCalibrationInC.map { .number($0) })
        ]
        let first = candidates.first { $0.1 != nil }
        self.init(entityId: entityId, timestamp: timestamp, uncheckedKind: first?.0.valueKind, value: first?.1, origin: origin, lastReport: lastReport)
    }
}
