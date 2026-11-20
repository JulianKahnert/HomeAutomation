//
//  HeatingFormat.swift
//  ControllerFeatures
//
//  German number and time formatting of the Heizung tab
//

import Foundation

enum HeatingFormat {
    static let locale = Locale(identifier: "de_DE")

    /// "21,5°"
    static func degrees(_ value: Double) -> String {
        "\(number(value))°"
    }

    /// "+1,2 K", "−0,8 K", "±0,0 K" for a value that rounds to zero.
    static func kelvin(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == 0 { return "±0,0 K" }
        let sign = rounded > 0 ? "+" : "−"
        return "\(sign)\(number(abs(rounded))) K"
    }

    /// "15.11. 22:40" for ranges over a day, "22:40" otherwise.
    static func time(_ date: Date, includingDay: Bool, calendar: Calendar = .current) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        style = includingDay ? style.day(.twoDigits).month(.twoDigits).hour().minute() : style.hour().minute()
        return date.formatted(style)
    }

    /// "Mo.", "Di." for the 7 d axis.
    static func weekday(_ date: Date, calendar: Calendar = .current) -> String {
        let name = date.formatted(Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated))
        return name.hasSuffix(".") ? name : name + "."
    }

    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded())) %"
    }

    private static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(locale))
    }
}
