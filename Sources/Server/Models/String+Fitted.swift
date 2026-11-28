//
//  String+Fitted.swift
//  HomeAutomationServer
//

extension String {
    /// The string cut to at most `limit` Unicode scalars. MySQL counts VARCHAR widths in code points, and in strict
    /// mode a longer value fails the whole insert instead of being cut.
    func fitted(toScalars limit: Int) -> String {
        guard unicodeScalars.count > limit else { return self }
        return String(String.UnicodeScalarView(unicodeScalars.prefix(limit)))
    }
}
