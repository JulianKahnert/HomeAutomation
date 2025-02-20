//
//  SettingsView.swift
//  HomeKitAdapterApp
//
//  Created by Julian Kahnert on 05.02.25.
//

import HAImplementations
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var serverAddress: CustomActorSystem.Address

    @State private var host = "localhost"
    @State private var port = 8888

    var newServerAddress: CustomActorSystem.Address {
        CustomActorSystem.Address(host: host, port: port)
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
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem {
                Button("Save") {
                    serverAddress = newServerAddress
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    SettingsView(serverAddress: .constant(.init(host: "localhost", port: 8888)))
}
