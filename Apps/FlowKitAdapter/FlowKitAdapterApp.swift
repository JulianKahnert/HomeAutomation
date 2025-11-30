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
    @AppStorage("ShouldCrashIfActorSystemInitFails") private var shouldCrashIfActorSystemInitFails = false
    @AppStorage("ActorSystemServerAddress") private var serverAddress = CustomActorSystem.Address(host: "localhost", port: 8888)
    @State private var logTask: Task<Void, Never>?
    @State private var entities: [EntityStorageItem] = []
    @State private var actorSystem: CustomActorSystem?
    @State private var reconnectionTask: Task<Void, Never>?

    var body: some Scene {
        WindowGroup {
            ContentView(
                shouldCrashIfActorSystemInitFails: $shouldCrashIfActorSystemInitFails,
                entities: $entities,
                actorSystem: actorSystem
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
                    reconnectionTask?.cancel()
                    await initializeActorSystem()
                }
            }
        }
    }

    private func initializeActorSystem() async {
        // Initialize with configured server address
        let system = await CustomActorSystem(
            nodeId: .homeKitAdapter,
            port: 7777,
            discovery: .staticEndpoint(serverAddress)
        )
        self.actorSystem = system

        let (entityStream, entityStreamContinuation) = AsyncStream.makeStream(
            of: EntityStorageItem.self, bufferingPolicy: .unbounded)
        let adapter = HomeKitAdapter(
            entityStream: entityStream,
            entityStreamContinuation: entityStreamContinuation)

        commandReceiver = system.makeLocalActor(actorId: .homeKitCommandReceiver) { actorSys in
            HomeKitCommandReceiver(actorSystem: actorSys, adapter: adapter)
        }
        _ = await system.checkIn(actorId: .homeKitCommandReceiver, commandReceiver)

        if shouldCrashIfActorSystemInitFails {
            do {
                try await system.waitForThisNode(is: .up, within: .seconds(10))
            } catch {
                fatalError("Actor system initialization failed: \(error)")
            }
        }

        // Start connection monitoring and reconnection logic
        reconnectionTask = Task {
            await monitorAndReconnect(system: system)
        }

        // Start entity processing loop
        Task {
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
                        if receiver == nil {
                            Self.log.error("Failed to resolve HomeEventReceiver actor")
                        }
                    }

                    // this might be very slow, when no server is connected
                    try await receiver?.process(event: .change(entity: entity))
                } catch {
                    Self.log.error("Failed to process event: \(error)")
                }
            }
        }
    }

    private func monitorAndReconnect(system: CustomActorSystem) async {
        var retryCount = 0
        let maxRetries = 5

        while !Task.isCancelled {
            // Check if we can reach the HomeEventReceiver
            let receiver = await system.lookup(.homeEventReceiver)

            if receiver == nil && retryCount < maxRetries {
                Self.log.warning("Lost connection to server, attempting reconnection (attempt \(retryCount + 1)/\(maxRetries))...")

                // Attempt to rejoin the cluster
                system.join(host: serverAddress.host, port: serverAddress.port)

                // Exponential backoff: 1s, 2s, 4s, 8s, then 5s intervals
                let delay = min(Double(1 << retryCount), 5.0)
                try? await Task.sleep(for: .seconds(delay))
                retryCount += 1
            } else if receiver != nil {
                // Connection healthy, reset retry count and check less frequently
                retryCount = 0
                try? await Task.sleep(for: .seconds(30))
            } else {
                // Max retries reached, wait longer before trying again
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }
}
