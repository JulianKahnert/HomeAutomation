//
//  ModelText+Localized.swift
//  Adapter
//
//  The Adapter's own wording for shared model values: HAModels stays free of resources, because the Server
//  builds it on Linux and uses its English text in summaries.
//

#if canImport(SwiftUI)
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
        case .off: String(localized: "Off", bundle: .module)
        case .heat: String(localized: "Heat", bundle: .module)
        case .cool: String(localized: "Cool", bundle: .module)
        case .auto: String(localized: "Auto", bundle: .module)
        }
    }
}
#endif
