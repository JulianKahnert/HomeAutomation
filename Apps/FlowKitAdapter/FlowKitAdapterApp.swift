//
//  FlowKit Adapter.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 28.05.24.
//

import Adapter
import Foundation
import HAImplementations
import HAModels
import Logging
import Shared
import StarActorSystem
import SwiftUI

@main
struct FlowKitApp {
    private static let log = Logger(label: "FlowKitAdapter")

    /// Entrypoint of the app
    static func main() {

        // we use this workaround to initialize the logging system before anything else is constructed
        initLogging(withFileLogging: true, logLevel: .debug)

        logStartupProvenance()

        // start the app
        FlowKitAdapter.main()
    }

    /// Logs the running build's version and binary build date at startup. The adapter is built and
    /// installed out-of-band from the server Docker image, so without this there is no way to tell
    /// from the logs which code (e.g. which connection fix) the deployed `.app` actually contains.
    private static func logStartupProvenance() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let buildDate: String = {
            guard let url = Bundle.main.executableURL,
                  let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let date = attrs[.modificationDate] as? Date else { return "unknown" }
            return ISO8601DateFormatter().string(from: date)
        }()
        Self.log.info("FlowKit Adapter starting — version \(version) (build \(build)), binary built \(buildDate)")
    }
}

struct FlowKitAdapter: App, Log {
    @AppStorage("ActorSystemServerAddress") private var serverAddress = ServerAddress(host: "localhost", port: 8080)
    @AppStorage("ServerAuthToken") private var serverAuthToken = ""
    @State private var entities: [EntityStorageItem] = []
    @State private var actorSystem: StarActorSystem?
    @State private var transport: URLSessionWebSocketTransport?
    @State private var commandReceiver: HomeKitCommandReceiver?
    @State private var connectionStatus: ConnectionStatus = .connecting
    @State private var statusObservationTask: Task<Void, Never>?
    @State private var handshakeObservationTask: Task<Void, Never>?
    @State private var entityObservationTask: Task<Void, Never>?

    var body: some Scene {
        WindowGroup {
            ContentView(
                entities: $entities,
                connectionStatus: $connectionStatus
            )
            .task(id: "\(serverAddress.rawValue)|\(serverAuthToken)") {
                Self.log.info("runloop task called for address: \(serverAddress)")

                // do not start run loop when running in preview canvas
                guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }

                // Tear down a previously-created system first (e.g. serverAddress or token changed)
                // so its transport loop stops before creating a new one.
                teardownActorSystem()
                initializeActorSystem()
            }
        }
    }

    private func teardownActorSystem() {
        statusObservationTask?.cancel()
        statusObservationTask = nil
        handshakeObservationTask?.cancel()
        handshakeObservationTask = nil
        entityObservationTask?.cancel()
        entityObservationTask = nil
        transport?.stop()
        transport = nil
        actorSystem = nil
        commandReceiver = nil
        connectionStatus = .connecting
    }

    private func initializeActorSystem() {
        let system = StarActorSystem(name: "adapter")

        let (entityStream, entityStreamContinuation) = AsyncStream.makeStream(
            of: EntityStorageItem.self, bufferingPolicy: .unbounded)
        let homeKitAdapter = HomeKitAdapter(
            entityStream: entityStream,
            entityStreamContinuation: entityStreamContinuation)

        let receiver = system.makeActor(id: .homeKitCommandReceiver) {
            HomeKitCommandReceiver(actorSystem: system, adapter: homeKitAdapter)
        }

        guard let url = URL(string: "ws://\(serverAddress.host):\(serverAddress.port)/adapter/v1") else {
            Self.log.error("Failed to build WebSocket URL from address \(serverAddress)")
            return
        }
        let transport = URLSessionWebSocketTransport(
            url: url,
            bearerToken: serverAuthToken.isEmpty ? nil : serverAuthToken,
            system: system)

        // The server's event receiver lives at a well-known ID — resolve it once;
        // reconnects are handled inside the transport, the proxy stays valid.
        let eventReceiver: HomeEventReceiver
        do {
            eventReceiver = try HomeEventReceiver.resolve(id: .homeEventReceiver, using: system)
        } catch {
            Self.log.error("Failed to resolve HomeEventReceiver proxy: \(error)")
            return
        }

        transport.start()
        // Cancellation-safety: if the surrounding .task was cancelled (e.g. the address
        // changed again while we were setting up), do not leak a half-initialized system.
        guard !Task.isCancelled else {
            transport.stop()
            return
        }
        self.actorSystem = system
        self.transport = transport
        self.commandReceiver = receiver

        // Feed the UI status indicator. UI only — the resync trigger below uses
        // the dedicated handshake stream, because this stream buffers only the
        // newest value and could swallow a rapid down/up transition.
        statusObservationTask = Task {
            for await status in system.makeConnectionStatusStream() {
                connectionStatus = status
            }
        }

        // Push the full HomeKit state on every completed handshake (including
        // the very first connect) so the server never misses events that
        // happened while the link was down. Unbounded buffering — no completed
        // handshake can ever be missed.
        handshakeObservationTask = Task {
            for await _ in system.makeHandshakeCompletedStream() {
                Self.log.info("handshake completed — pushing full state")
                await homeKitAdapter.pushFullState()
            }
        }

        // Start long lived entity processing loop
        entityObservationTask = Task {
            for await entity in entityStream {
                // saving the data locally for the ui
                self.entities = self.entities.suffix(99) + [entity]

                do {
                    try await eventReceiver.process(event: .change(entity: entity))
                } catch {
                    Self.log.error("Failed to process event: \(error)")
                }
            }
        }
    }
}
