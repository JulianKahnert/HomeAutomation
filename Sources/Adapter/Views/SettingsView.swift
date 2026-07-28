//
//  SettingsView.swift
//  FlowKit Adapter
//
//  Created by Julian Kahnert on 05.02.25.
//

#if canImport(SwiftUI)
import Shared
import StarActorSystem
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var serverAddress: ServerAddress
    @AppStorage("ServerAuthToken") private var serverAuthToken = ""

    @State private var host = "localhost"
    @State private var port = 8080
    @State private var token = ""

    var newServerAddress: ServerAddress {
        ServerAddress(host: host, port: port)
    }

    var body: some View {
        Form {
            Section {
                TextField("Host", text: $host)
                TextField("Port", value: $port, format: .number.grouping(.never))
            } header: {
                Text("Home Automation Server")
            } footer: {
                Text("Websocket endpoint: \(newServerAddress.description)")
            }
            Section {
                SecureField("Auth Token", text: $token)
            } header: {
                Text("Authentication")
            } footer: {
                Text("Bearer token used when connecting to the server. Leave empty if authentication is disabled.")
            }
        }
        .onAppear {
            token = serverAuthToken
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem {
                Button("Save") {
                    serverAddress = newServerAddress
                    serverAuthToken = token
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    SettingsView(serverAddress: .constant(.init(host: "localhost", port: 8080)))
}
#endif
