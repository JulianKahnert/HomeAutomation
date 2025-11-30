//
//  ContentView.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 26.07.24.
//

import Adapter
import HAModels
import Shared
import SwiftUI

struct ContentView: View {
    @Binding var shouldCrashIfActorSystemInitFails: Bool
    @Binding var entities: [EntityStorageItem]
    let actorSystem: CustomActorSystem?
    @State private var showSettings = false
    @State private var connectionStatus: ConnectionStatus = .joining
    @AppStorage("ActorSystemServerAddress") private var serverAddress = CustomActorSystem.Address(host: "localhost", port: 8888)

    var body: some View {
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
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ConnectionStatusView(status: connectionStatus)
                }
            }
            .task {
                // Update connection status periodically
                while !Task.isCancelled {
                    if let system = actorSystem {
                        connectionStatus = await system.connectionStatus
                    }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
    }
}

struct ConnectionStatusView: View {
    let status: ConnectionStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)
            Text(statusText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var statusColor: Color {
        switch status {
        case .up:
            return .green
        case .joining:
            return .yellow
        case .error:
            return .red
        }
    }

    private var statusText: String {
        switch status {
        case .up:
            return "Connected"
        case .joining:
            return "Connecting..."
        case .error:
            return "Connection Error"
        }
    }
}

#Preview {
    ContentView(shouldCrashIfActorSystemInitFails: .constant(true), entities: .constant([]), actorSystem: nil)
}
