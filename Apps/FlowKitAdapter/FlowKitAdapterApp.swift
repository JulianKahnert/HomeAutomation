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
import SwiftUI

@MainActor var commandReceiver: HomeKitCommandReceiver!

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
    /// from the logs which code (e.g. which cluster fix) the deployed `.app` actually contains.
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
    @AppStorage("ActorSystemServerAddress") private var serverAddress = CustomActorSystem.Address(host: "localhost", port: 8888)
    @State private var entities: [EntityStorageItem] = []
    @State private var actorSystem: CustomActorSystem?
    @State private var connectionStatus: ConnectionStatus = .joining
    @State private var statusObservationTask: Task<Void, Never>?
    @State private var entityObservationTask: Task<Void, Never>?

    var body: some Scene {
        WindowGroup {
            ContentView(
                entities: $entities,
                connectionStatus: $connectionStatus
            )
            .task(id: serverAddress) {
                Self.log.info("runloop task called for address: \(serverAddress)")

                // do not start run loop when running in preview canvas
                guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }

                // Tear down a previously-created system first (e.g. serverAddress changed) so its
                // cluster node, background tasks and bound port are released before creating a new one.
                await teardownActorSystem()

                try? await Task.sleep(for: .seconds(1))
                await initializeActorSystem()
            }
        }
    }

    private func teardownActorSystem() async {
        statusObservationTask?.cancel()
        statusObservationTask = nil
        entityObservationTask?.cancel()
        entityObservationTask = nil
        if let actorSystem {
            await actorSystem.shutdown()
            self.actorSystem = nil
        }
    }

    private func initializeActorSystem() async {
        // Initialize with configured server address.
        // onDown: a lost connection that does not recover within the grace period restarts the app
        // (launchctl KeepAlive) with a fresh node UID → clean re-handshake with the server.
        let system = await CustomActorSystem(role: .homeKitAdapter(serverAddress: serverAddress), onDown: {
            exit(1)
        })
        self.actorSystem = system

        let (entityStream, entityStreamContinuation) = AsyncStream.makeStream(
            of: EntityStorageItem.self, bufferingPolicy: .unbounded)
        let adapter = HomeKitAdapter(
            entityStream: entityStream,
            entityStreamContinuation: entityStreamContinuation)

        commandReceiver = await system.makeLocalActor(actorId: .homeKitCommandReceiver) { @Sendable actorSys in
            HomeKitCommandReceiver(actorSystem: actorSys, adapter: adapter)
        }
        _ = await system.checkIn(actorId: .homeKitCommandReceiver, commandReceiver)

        statusObservationTask?.cancel()
        statusObservationTask = Task {
            for await status in await system.makeConnectionStatusStream() {
                connectionStatus = status
            }
        }

        // Start long lived entity processing loop
        entityObservationTask?.cancel()
        entityObservationTask = Task {
            var receiver: HomeEventReceiver?
            Task {
                for await foundReceiver in await system.listing(of: .homeEventReceiver) {
                    Self.log.info("Get new HomeEventReceiver")
                    receiver = foundReceiver
                }
            }

            for await entity in entityStream {
                // saving the data locally for the ui
                self.entities = self.entities.suffix(99) + [entity]

                do {
                    if receiver == nil {
                        receiver = await system.lookup(.homeEventReceiver)
                    }
                    if receiver == nil {
                        Self.log.error("Failed to resolve HomeEventReceiver actor")
                    }

                    // this might be very slow, when no server is connected
                    try await receiver?.process(event: .change(entity: entity))
                } catch {
                    Self.log.error("Failed to process event: \(error)")
                }
            }
        }
    }
}
