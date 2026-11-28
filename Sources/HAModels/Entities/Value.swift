//
//  Value.swift
//  HAModels
//

import Foundation

/// The one value a state carries: a Bool, a number or a text.
public enum Value: Hashable, Sendable, Codable {
    case bool(Bool)
    case number(Double)
    case text(String)
}
