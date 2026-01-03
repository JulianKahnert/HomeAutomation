//
//  FlowKit Adapter.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 28.05.24.
//

import Adapter
import HAImplementations
import HAModels
import Shared
import SwiftUI

@MainActor var commandReceiver: HomeKitCommandReceiver!

@main
struct FlowKitApp {
    /// Entrypoint of the app
    static func main() {

        // we use this workaround to initialize the logging system before anything else is constructed
        initLogging(withFileLogging: true, logLevel: .debug)

        // start the app
        FlowKitAdapter.main()
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
            .task {
                Self.log.info("runloop task called")

                // do not start run loop when running in preview canvas
                guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }

                try? await Task.sleep(for: .seconds(1))
                await initializeActorSystem()
            }
            .onChange(of: serverAddress) { _, newValue in
                Task {
                    Self.log.info("Server address changed to \(newValue), reinitializing actor system")
                    await initializeActorSystem()
                }
            }
        }
    }

    private func initializeActorSystem() async {
        // Initialize with configured server address
        let system = await CustomActorSystem(role: .homeKitAdapter(serverAddress: serverAddress))
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
            for await status in await system.connectionStatus {
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
