//
//  Location.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 05.02.25.
//

public struct Location: Sendable, Codable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}
