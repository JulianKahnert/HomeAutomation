//
//  ContentView.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 26.07.24.
//

import HAModels
import SwiftUI

struct ContentView: View {
    @Binding var shouldCrashIfActorSystemInitFails: Bool
    @Binding var entities: [EntityStorageItem]

    var body: some View {
        TabView {
            // Tab 1: Existing entities list
            EntitiesListView(shouldCrashIfActorSystemInitFails: $shouldCrashIfActorSystemInitFails, entities: $entities)
                .tabItem {
                    Label("Entities", systemImage: "list.bullet")
                }

            // Tab 2: New actions list
            ActionsListView()
                .tabItem {
                    Label("Actions", systemImage: "bolt.fill")
                }
        }
    }
}

#Preview {
    ContentView(shouldCrashIfActorSystemInitFails: .constant(true), entities: .constant([]))
}
