//
//  ServerOwnedEntity.swift
//  HAModels
//

import Foundation

public extension EntityId {
    /// The place of every server-owned entity (glossary): a state the server keeps itself, not HomeKit.
    static let serverOwnedPlaceId: PlaceId = "server"

    /// A server-owned entity named `name`; its value kind is `characteristic`.
    static func serverOwned(name: String, characteristic: CharacteristicsType) -> EntityId {
        EntityId(placeId: serverOwnedPlaceId, name: name, characteristicsName: nil, characteristic: characteristic)
    }

    /// The current outdoor temperature, reported hourly by the server's `OutdoorTemperatureJob`.
    static let outdoorTemperature = serverOwned(name: "outdoor", characteristic: .temperatureSensor)

    /// The current electricity price, reported by the server's `EnergyPriceJob`.
    static let electricityPrice = serverOwned(name: "electricityPrice", characteristic: .energyPrice)

    /// Whether the server keeps this entity itself. `POST /config` accepts it without HomeKit knowing it (ADR-009).
    var isServerOwned: Bool { placeId == Self.serverOwnedPlaceId }
}
