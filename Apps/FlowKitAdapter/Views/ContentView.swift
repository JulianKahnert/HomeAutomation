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
    @State private var selectedTab = "entities"
    @AppStorage("ActorSystemServerAddress") private var serverAddress = CustomActorSystem.Address(host: "localhost", port: 8888)

    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: Existing entities list
            Tab("Entities", systemImage: "list.bullet", value: "entities") {
                NavigationStack {
                    EntitiesListView(
                        shouldCrashIfActorSystemInitFails: $shouldCrashIfActorSystemInitFails,
                        entities: $entities,
                        serverAddress: $serverAddress,
                        showSettings: $showSettings
                    )
                    .navigationDestination(isPresented: $showSettings) {
                        SettingsView(serverAddress: $serverAddress)
                    }
                }
            }
            
            // Tab 2: New actions list
            Tab(value: "search", role: .search) {
                NavigationStack {
                    ActionsListView()
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

#Preview {
    ContentView(shouldCrashIfActorSystemInitFails: .constant(true), entities: .constant([]))
}
