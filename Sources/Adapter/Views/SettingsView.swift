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
    @Environment(AdapterCredentialStore.self) private var credentials: AdapterCredentialStore?

    @State private var host = "localhost"
    @State private var port = 8080
    @State private var useTLS = false
    @State private var token = ""

    var newServerAddress: ServerAddress {
        ServerAddress(host: host, port: port, useTLS: useTLS)
    }

    var body: some View {
        Form {
            Section {
                TextField("Host", text: $host)
                TextField("Port", value: $port, format: .number.grouping(.never))
                Toggle("Use TLS (wss://)", isOn: $useTLS)
            } header: {
                Text("Home Automation Server")
            } footer: {
                Text("Websocket endpoint: \(newServerAddress.description)\nWithout TLS the auth token and all HomeKit traffic cross the network unencrypted.")
            }
            Section {
                SecureField("Auth Token", text: $token)
            } header: {
                Text("Authentication")
            } footer: {
                Text("Bearer token used when connecting to the server. Stored in the keychain. Leave empty if authentication is disabled.")
            }
        }
        .onAppear {
            host = serverAddress.host
            port = serverAddress.port
            useTLS = serverAddress.useTLS
            token = credentials?.authToken ?? ""
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem {
                Button("Save") {
                    serverAddress = newServerAddress
                    credentials?.update(authToken: token)
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    SettingsView(serverAddress: .constant(.init(host: "localhost", port: 8080)))
        .environment(AdapterCredentialStore())
}
#endif
