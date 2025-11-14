//
//  ContentView.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 26.07.24.
//

import Adapter
import HAModels
import SwiftUI

struct ContentView: View {
    @Binding var shouldCrashIfActorSystemInitFails: Bool
    @Binding var entities: [EntityStorageItem]
    @State private var showSettings = false
    @AppStorage("ActorSystemServerAddress") private var serverAddress = CustomActorSystem.Address(host: "localhost", port: 8888)

    var body: some View {
        TabView {
            // Tab 1: Existing entities list
            EntitiesListView(
                shouldCrashIfActorSystemInitFails: $shouldCrashIfActorSystemInitFails,
                entities: $entities,
                serverAddress: $serverAddress,
                showSettings: $showSettings
            )
            .tabItem {
                Label("Entities", systemImage: "list.bullet")
            }

            // Tab 2: New actions list
            ActionsListView()
                .tabItem {
                    Label("Actions", systemImage: "bolt.fill")
                }
        }
        .navigationDestination(isPresented: $showSettings) {
            SettingsView(serverAddress: $serverAddress)
        }
    }
}

#Preview {
    ContentView(shouldCrashIfActorSystemInitFails: .constant(true), entities: .constant([]))
}
