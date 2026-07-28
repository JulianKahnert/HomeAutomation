//
//  AdapterConnection.swift
//  Adapter
//

#if canImport(HomeKit)
import Foundation
import HAModels
import Logging
import Observation
import StarActorSystem

/// Lean facade owning the adapter's whole connection stack: the `StarActorSystem`,
/// the WebSocket transport, the `HomeKitCommandReceiver`, the `HomeKitAdapter`
/// and all observation tasks (UI status, resync-on-handshake, entity pump).
///
/// The app only creates/starts/stops this object and reads its observable
/// `connectionStatus` and `entities`.
@MainActor
@Observable
public final class AdapterConnection {
    private static let log = Logger(label: "AdapterConnection")

    public private(set) var connectionStatus: ConnectionStatus = .connecting
    public private(set) var entities: [EntityStorageItem] = []

    private let system: StarActorSystem
    private let transport: URLSessionWebSocketTransport
    private let homeKitAdapter: HomeKitAdapter
    // Held strongly so the local distributed actor stays registered for the system's lifetime.
    private let commandReceiver: HomeKitCommandReceiver
    private let eventReceiver: HomeEventReceiver
    private let entityStream: AsyncStream<EntityStorageItem>
    private var observationTasks: [Task<Void, Never>] = []

    /// Returns nil when no valid WebSocket URL can be built from the address
    /// or the server's event-receiver proxy cannot be resolved.
    public init?(address: ServerAddress, authToken: String) {
        guard let url = URL(string: "ws://\(address.host):\(address.port)/adapter/v1") else {
            Self.log.error("Failed to build WebSocket URL from address \(address)")
            return nil
        }

        let system = StarActorSystem(name: "adapter")

        let (entityStream, entityStreamContinuation) = AsyncStream.makeStream(
            of: EntityStorageItem.self, bufferingPolicy: .unbounded)
        let homeKitAdapter = HomeKitAdapter(
            entityStream: entityStream,
            entityStreamContinuation: entityStreamContinuation)

        do {
            // The server's event receiver lives at a well-known ID — resolve it once;
            // reconnects are handled inside the transport, the proxy stays valid.
            self.eventReceiver = try HomeEventReceiver.resolve(id: .homeEventReceiver, using: system)
        } catch {
            Self.log.error("Failed to resolve HomeEventReceiver proxy: \(error)")
            return nil
        }

        self.system = system
        self.entityStream = entityStream
        self.homeKitAdapter = homeKitAdapter
        self.commandReceiver = system.makeActor(id: .homeKitCommandReceiver) {
            HomeKitCommandReceiver(actorSystem: system, adapter: homeKitAdapter)
        }
        self.transport = URLSessionWebSocketTransport(
            url: url,
            bearerToken: authToken.isEmpty ? nil : authToken,
            system: system)
    }

    public func start() {
        transport.start()

        // Feed the UI status indicator. UI only — the resync trigger below uses
        // the dedicated handshake stream, because this stream buffers only the
        // newest value and could swallow a rapid down/up transition.
        observationTasks.append(Task { [system] in
            for await status in system.makeConnectionStatusStream() {
                self.connectionStatus = status
            }
        })

        // Push the full HomeKit state on every completed handshake (including
        // the very first connect) so the server never misses events that
        // happened while the link was down. Unbounded buffering — no completed
        // handshake can ever be missed.
        observationTasks.append(Task { [system, homeKitAdapter] in
            for await _ in system.makeHandshakeCompletedStream() {
                Self.log.info("handshake completed — pushing full state")
                await homeKitAdapter.pushFullState()
            }
        })

        // Long lived entity processing loop: keep the last 100 items for the UI,
        // forward every change to the server.
        observationTasks.append(Task { [entityStream, eventReceiver] in
            for await entity in entityStream {
                self.entities = self.entities.suffix(99) + [entity]

                do {
                    try await eventReceiver.process(event: .change(entity: entity))
                } catch {
                    Self.log.error("Failed to process event: \(error)")
                }
            }
        })
    }

    public func stop() {
        for task in observationTasks {
            task.cancel()
        }
        observationTasks = []
        transport.stop()
    }
}
#endif
