//
//  ValueKind.swift
//  HAModels
//

import Foundation

/// The kind of value a state carries (glossary: value kind). It is a name, so a kind this build does not
/// know survives decoding; ``descriptor`` is `nil` for it.
public struct ValueKind: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ type: CharacteristicsType) {
        self.init(rawValue: type.rawValue)
    }

    /// The characteristic type of this kind, `nil` for a kind this build does not know.
    public var characteristicsType: CharacteristicsType? {
        CharacteristicsType(rawValue: rawValue)
    }

    /// The descriptor of this kind, `nil` for a kind this build does not know.
    public var descriptor: ValueDescriptor? {
        characteristicsType.map(ValueDescriptor.descriptor(for:))
    }
}

public extension CharacteristicsType {
    var valueKind: ValueKind { ValueKind(self) }
}

/// The one value a state carries: a Bool, a number or a text.
public enum Value: Hashable, Sendable, Codable {
    case bool(Bool)
    case number(Double)
    case text(String)
}
