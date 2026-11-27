//
//  Thermostat.swift
//  HAModels
//

import Foundation

/// One thermostat valve device the adapter can read, named by its room, accessory and heating service.
///
/// Part of the adapter wire format: additive changes only.
public struct Thermostat: Hashable, Sendable, Codable, CustomStringConvertible {
    public let placeId: String
    public let name: String
    public let characteristicsName: String?

    public init(placeId: String, name: String, characteristicsName: String?) {
        self.placeId = placeId
        self.name = name
        self.characteristicsName = characteristicsName
    }

    public var description: String { "\(name) [\(placeId)]" }
}
