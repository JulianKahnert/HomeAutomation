//
//  HomeEventReceiver.swift
//  Shared
//
//  Created by Julian Kahnert on 31.01.25.
//

import Distributed
import HAModels
import Logging
import Shared
import StarActorSystem

/// Receiver of HomeKitEvents
///
/// This should be instantiated on the server.
public distributed actor HomeEventReceiver {
    private let log = Logger(label: "HomeEventReceiver")

    public typealias ActorSystem = StarActorSystem

    private let emit: @Sendable (HomeEvent) -> Void
    private let storeInventory: @Sendable ([HomeKitInventoryItem]) async throws -> Void

    /// - Parameters:
    ///   - emit: Hands an incoming event to the server's event stream.
    ///   - storeInventory: Replaces the stored HomeKit inventory with a snapshot.
    public init(emit: @escaping @Sendable (HomeEvent) -> Void,
                storeInventory: @escaping @Sendable ([HomeKitInventoryItem]) async throws -> Void = { _ in },
                actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
        self.emit = emit
        self.storeInventory = storeInventory
    }

    /// Replaces the stored HomeKit inventory with the adapter's snapshot of everything HomeKit knows.
    public distributed func process(inventory: [HomeKitInventoryItem]) async throws {
        log.info("Storing HomeKit inventory", metadata: ["characteristics": "\(inventory.count)"])
        try await storeInventory(inventory)
    }

    /// process  an incoming HomeKit event
    ///
    /// return: true when processing was successfull
    public distributed func process(event: HomeEvent) {
        log.debug("Processing incoming event: \(event)")
        emit(Self.stamped(event))
    }

    /// Everything that comes in over the adapter link is a report from HomeKit, whatever the
    /// adapter wrote into the item.
    static func stamped(_ event: HomeEvent) -> HomeEvent {
        guard case .change(var item) = event else { return event }
        item.origin = .homekit
        return .change(entity: item)
    }
}
