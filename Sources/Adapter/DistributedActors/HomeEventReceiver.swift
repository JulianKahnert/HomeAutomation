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

    private var continuation: AsyncStream<HomeEvent>.Continuation

    public init(continuation: AsyncStream<HomeEvent>.Continuation, actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
        self.continuation = continuation
    }

    /// process  an incoming HomeKit event
    ///
    /// return: true when processing was successfull
    public distributed func process(event: HomeEvent) {
        log.debug("Processing incoming event: \(event)")
        continuation.yield(Self.stamped(event))
    }

    /// Everything that comes in over the adapter link is a report from HomeKit, whatever the
    /// adapter wrote into the item.
    static func stamped(_ event: HomeEvent) -> HomeEvent {
        guard case .change(var item) = event else { return event }
        item.origin = .homekit
        return .change(entity: item)
    }
}

extension HomeEventReceiver {
    public struct Event: Codable, Sendable {
        public let type: String
        public let payload: [String: String]

        public init(type: String, payload: [String: String]) {
            self.type = type
            self.payload = payload
        }
    }
}
