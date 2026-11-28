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
    /// Draft of `storedDebugLogging`, written on Save like the other settings.
    @State private var isDebugLoggingEnabled = false
    /// The app reads this key once at launch (`DebugLogging`), so it lives in `UserDefaults`, not the keychain.
    @AppStorage(DebugLogging.key) private var storedDebugLogging = false

    var newServerAddress: ServerAddress {
        ServerAddress(host: host, port: port, useTLS: useTLS)
    }

    var body: some View {
        Form {
            Section {
                TextField(String(localized: "Host", bundle: .module), text: $host)
                TextField(String(localized: "Port", bundle: .module), value: $port, format: .number.grouping(.never))
                Toggle(String(localized: "Use TLS (wss://)", bundle: .module), isOn: $useTLS)
            } header: {
                Text("Home Automation Server", bundle: .module)
            } footer: {
                Text("Websocket endpoint: \(newServerAddress.description)\nWithout TLS the auth token and all HomeKit traffic cross the network unencrypted.", bundle: .module)
            }
            Section {
                SecureField(String(localized: "Auth Token", bundle: .module), text: $token)
            } header: {
                Text("Authentication", bundle: .module)
            } footer: {
                Text("Bearer token used when connecting to the server. Stored in the keychain. Leave empty if authentication is disabled.", bundle: .module)
            }
            Section {
                Toggle(String(localized: "Debug Logs", bundle: .module), isOn: $isDebugLoggingEnabled)
            } header: {
                Text("Logging", bundle: .module)
            } footer: {
                Text("Writes debug logs, e.g. every thermostat value. Takes effect after restarting the app. The environment variable \(DebugLogging.key) overrides this setting.", bundle: .module)
            }
        }
        .onAppear {
            host = serverAddress.host
            port = serverAddress.port
            useTLS = serverAddress.useTLS
            token = credentials?.authToken ?? ""
            isDebugLoggingEnabled = storedDebugLogging
        }
        .navigationTitle(String(localized: "Settings", bundle: .module))
        .toolbar {
            ToolbarItem {
                Button(String(localized: "Save", bundle: .module)) {
                    serverAddress = newServerAddress
                    credentials?.update(authToken: token)
                    storedDebugLogging = isDebugLoggingEnabled
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
