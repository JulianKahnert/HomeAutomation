//
//  ContentView.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 26.07.24.
//

#if canImport(SwiftUI)
import HAModels
import Shared
import StarActorSystem
import SwiftUI

public struct ContentView: View {
    @Binding var entities: [EntityStorageItem]
    @Binding var connectionStatus: ConnectionStatus
    @State private var showSettings = false
    @AppStorage("ActorSystemServerAddress") private var serverAddress = ServerAddress(host: "localhost", port: 8080)

    public init(entities: Binding<[EntityStorageItem]>, connectionStatus: Binding<ConnectionStatus>) {
        self._entities = entities
        self._connectionStatus = connectionStatus
    }

    public var body: some View {
        NavigationStack {
            EntitiesListView(
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
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    ConnectionStatusView(status: connectionStatus)
                }
            }
        }
    }
}

struct ConnectionStatusView: View {
    let status: ConnectionStatus

    var body: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 12, height: 12)
    }

    private var statusColor: Color {
        switch status {
        case .up:
            return .green
        case .connecting:
            return .yellow
        case .error:
            return .red
        }
    }
}

#Preview {
    ContentView(entities: .constant([]), connectionStatus: .constant(.connecting))
}
#endif
