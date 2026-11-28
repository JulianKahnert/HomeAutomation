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

    /// - Parameter emit: Hands an incoming event to the server's event stream.
    public init(emit: @escaping @Sendable (HomeEvent) -> Void, actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
        self.emit = emit
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
