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
    @State private var logTask: Task<Void, Never>?
    @State private var entities: [EntityStorageItem] = []

    var body: some Scene {
        WindowGroup {
            ContentView(shouldCrashIfActorSystemInitFails: $shouldCrashIfActorSystemInitFails, entities: $entities)
            .task {
                Self.log.info("runloop task called")

                // do not start run loop when running in preview canvas
                guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }

                try? await Task.sleep(for: .seconds(1))
                let actorSystem = await CustomActorSystem(nodeId: .homeKitAdapter, port: 7777)

                let (entityStream, entityStreamContinuation) = AsyncStream.makeStream(
                    of: EntityStorageItem.self, bufferingPolicy: .unbounded)
                let adapter = HomeKitAdapter(
                    entityStream: entityStream,
                    entityStreamContinuation: entityStreamContinuation)

                // MARK: - Device Debug Helper (uncomment for development)

                #if DEBUG
                // Print all accessories to find the entityId you want to inspect
                Task {
                    try? await Task.sleep(for: .seconds(5))  // Wait for adapter to initialize
                    await adapter.debugPrintAllAccessories()

                    // Then inspect a specific device by its entityId
                    // Copy an entityId from the output above
                    let entityId = EntityId(
                        placeId: "Garage",
                        name: "Anwesenheitssensor",
                        characteristicsName: nil,
                        characteristic: .motionSensor
                    )
                    await adapter.debugPrintAccessory(entityId: entityId)
                }
                #endif

                commandReceiver = actorSystem.makeLocalActor(actorId: .homeKitCommandReceiver) { system in
                    HomeKitCommandReceiver(actorSystem: system, adapter: adapter)
                }
                _ = await actorSystem.checkIn(actorId: .homeKitCommandReceiver, commandReceiver)

                if shouldCrashIfActorSystemInitFails {
                    do {
                        try await actorSystem.waitForThisNode(is: .up, within: .seconds(10))
                    } catch {
                        fatalError("Actor system initialization failed: \(error)")
                    }
                }

                var receiver: HomeEventReceiver?
                Task {
                    for await foundReceiver in await actorSystem.listing(of: .homeEventReceiver) {
                        Self.log.info("Get new HomeEventReceiver")
                        receiver = foundReceiver
                    }
                }

                for await entity in entityStream {
                    // saving the data locally for the ui
                    self.entities = self.entities.suffix(99) + [entity]

                    do {
                        if receiver == nil {
                            receiver = await actorSystem.lookup(.homeEventReceiver)
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
    }
}
