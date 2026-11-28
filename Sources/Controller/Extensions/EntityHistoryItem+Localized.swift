//
//  EntityHistoryItem+Localized.swift
//  Controller
//
//  The Controller's own wording for shared model values: HAModels stays free of resources, because the
//  Server builds it on Linux and uses its English `valueDescription` in automation summaries.
//

import Foundation
import HAModels

extension Deadline {
    /// How a deadline reads in a list: the case and, when it has one, the time of day of its end.
    func localizedDisplayText(locale: Locale = .autoupdatingCurrent) -> String {
        let style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale)
        switch self {
        case .none:
            return String(localized: "No deadline", bundle: .module)
        case .running(let until):
            return String(localized: "Until \(until.formatted(style))", bundle: .module)
        case .overdue(let since):
            return String(localized: "Overdue since \(since.formatted(style))", bundle: .module)
        }
    }
}

extension HeatingMode {
    /// The mode's name for people; `name` stays the value of the HTTP API.
    var localizedName: String {
        switch self {
        case .off: String(localized: "history.value.off", defaultValue: "Off", bundle: .module)
        case .heat: String(localized: "Heat", bundle: .module)
        case .cool: String(localized: "Cool", bundle: .module)
        case .auto: String(localized: "Auto", bundle: .module)
        }
    }
}

extension EntityHistoryItem {
    /// `valueDescription` in the user's language and number format; units like °C, %, ppm and lux stay as they are.
    func localizedValueDescription(locale: Locale = .autoupdatingCurrent) -> String {
        func decimal(_ value: Double, fractionDigits: Int = 1) -> String {
            value.formatted(.number.precision(.fractionLength(fractionDigits)).locale(locale))
        }

        if let valueKind, descriptor == nil, let rawValueDescription {
            return "\(valueKind): \(rawValueDescription)"
        }
        if valueKind == CharacteristicsType.deadline.rawValue, case .text(let text) = value, let deadline = Deadline(text: text) {
            return deadline.localizedDisplayText(locale: locale)
        }
        if let temperatureInC {
            return "\(decimal(temperatureInC))°C"
        }
        if let relativeHumidity {
            return "\(decimal(relativeHumidity))%"
        }
        if let carbonDioxideSensorId {
            return "\(carbonDioxideSensorId) ppm"
        }
        if let airQuality {
            return "AQI: \(airQuality)"
        }
        if let pmDensity {
            return "\(decimal(pmDensity)) µg/m³"
        }
        if let illuminanceInLux {
            return "\(decimal(illuminanceInLux)) lux"
        }
        if let brightness {
            return "\(brightness)%"
        }
        if let stateOfCharge {
            return "\(stateOfCharge)%"
        }
        if let colorTemperature {
            return "CT: \(decimal(Double(colorTemperature), fractionDigits: 2))"
        }
        if let isDeviceOn {
            return isDeviceOn ? String(localized: "history.value.on", defaultValue: "On", bundle: .module) : String(localized: "history.value.off", defaultValue: "Off", bundle: .module)
        }
        if let motionDetected {
            return motionDetected ? String(localized: "Motion", bundle: .module) : String(localized: "No motion", bundle: .module)
        }
        if let isContactOpen {
            return isContactOpen ? String(localized: "Open", bundle: .module) : String(localized: "Closed", bundle: .module)
        }
        if let isDoorLocked {
            return isDoorLocked ? String(localized: "Locked", bundle: .module) : String(localized: "Unlocked", bundle: .module)
        }
        if let isHeaterActive {
            return isHeaterActive ? String(localized: "Active", bundle: .module) : String(localized: "Inactive", bundle: .module)
        }
        if let valveOpen {
            return valveOpen ? String(localized: "Open", bundle: .module) : String(localized: "Closed", bundle: .module)
        }
        if let valvePositionPercent {
            return String(localized: "Valve \(valvePositionPercent)%", bundle: .module)
        }
        if let temperatureCalibrationInC {
            let offset = temperatureCalibrationInC.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always()).locale(locale))
            return String(localized: "Offset \(offset)°C", bundle: .module)
        }
        if let targetTemperatureInC {
            return String(localized: "Target \(decimal(targetTemperatureInC))°C", bundle: .module)
        }
        if let heatingMode {
            return String(localized: "Mode \(heatingMode.localizedName)", bundle: .module)
        }
        if let rgb {
            return String(localized: "\(decimal(Double(rgb.hue), fractionDigits: 0))° hue", bundle: .module)
        }
        return String(localized: "history.value.noData", defaultValue: "No data", bundle: .module)
    }
}
