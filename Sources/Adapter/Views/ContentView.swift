//
//  ContentView.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 26.07.24.
//

#if canImport(SwiftUI)
import Adapter
import HAModels
import SwiftUI

public struct ContentView: View {
    @Binding var shouldCrashIfActorSystemInitFails: Bool
    @Binding var entities: [EntityStorageItem]
    @State private var showSettings = false
    @AppStorage("ActorSystemServerAddress") private var serverAddress = CustomActorSystem.Address(host: "localhost", port: 8888)

    public init(shouldCrashIfActorSystemInitFails: Binding<Bool>, entities: Binding<[EntityStorageItem]>) {
        self._shouldCrashIfActorSystemInitFails = shouldCrashIfActorSystemInitFails
        self._entities = entities
    }

    public var body: some View {
        NavigationStack {
            EntitiesListView(
                shouldCrashIfActorSystemInitFails: $shouldCrashIfActorSystemInitFails,
                entities: $entities,
                showSettings: $showSettings
            )
            .navigationTitle(serverAddress.description)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(isPresented: $showSettings) {
                SettingsView(serverAddress: $serverAddress)
                    .navigationTitle("Settings")
            }
        }
    }
}

#Preview {
    ContentView(shouldCrashIfActorSystemInitFails: .constant(true), entities: .constant([]))
}
#endif
