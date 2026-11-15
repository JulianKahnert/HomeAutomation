//
//  WindowOpenState.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 13.03.25.
//

import Foundation

/// An offenes Fenster as the server tracks it.
public struct WindowOpenState: Hashable, Encodable, Sendable {
    /// Stable across updates, derived from the window's entity.
    public let id: String
    /// The window name without the room.
    public let name: String
    /// The Raum the window is in.
    public let room: String
    public let opened: Date
    /// The Lüftungslimit.
    public let maxOpenDuration: TimeInterval

    /// The Fensterschließzeit: opened + Lüftungslimit.
    public var closeBy: Date {
        opened.addingTimeInterval(maxOpenDuration)
    }

    public init(entityId: EntityId, opened: Date, maxOpenDuration: TimeInterval) {
        id = WindowContentState.Window.id(room: entityId.placeId, name: entityId.name)
        name = entityId.name
        room = entityId.placeId
        self.opened = opened
        self.maxOpenDuration = maxOpenDuration
    }
}
