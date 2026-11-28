//
//  HeatingFormat.swift
//  ControllerFeatures
//
//  Locale-aware number and time formatting of the Heating tab
//

import Foundation

/// Every function takes the locale to format with; views pass their `\.locale` environment, the default follows the user's settings.
enum HeatingFormat {
    /// "21.5°" / "21,5°"
    static func degrees(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        "\(number(value, locale: locale))°"
    }

    /// "+1.2 K", "−0.8 K", "±0.0 K" for a value that rounds to zero.
    static func kelvin(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == 0 { return "±\(number(0, locale: locale)) K" }
        let sign = rounded > 0 ? "+" : "−"
        return "\(sign)\(number(abs(rounded), locale: locale)) K"
    }

    /// "3.7 K": the size of a deviation without its sign.
    static func kelvinAmount(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        "\(number(abs((value * 10).rounded() / 10), locale: locale)) K"
    }

    /// The time of day, with day and month in front for ranges over a day.
    static func time(_ date: Date, includingDay: Bool, calendar: Calendar = .current, locale: Locale = .autoupdatingCurrent) -> String {
        let style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let time = date.formatted(style.hour().minute())
        guard includingDay else { return time }
        return "\(date.formatted(style.day(.twoDigits).month(.twoDigits))) \(time)"
    }

    /// The abbreviated weekday for the 7 d axis ("Mo." in German, "Mon" in English).
    static func weekday(_ date: Date, calendar: Calendar = .current, locale: Locale = .autoupdatingCurrent) -> String {
        let name = date.formatted(Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated))
        // German abbreviations carry the dot ("Mo."); the system format leaves it out.
        return locale.language.languageCode == .german && !name.hasSuffix(".") ? name + "." : name
    }

    static func percent(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    private static func number(_ value: Double, locale: Locale) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(locale))
    }
}
