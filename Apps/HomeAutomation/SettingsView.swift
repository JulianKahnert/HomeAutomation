//
//  SettingsView.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 28.02.25.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var serverAddress: URL

    @State private var host = "localhost"
    @State private var port = 8080

    private var newServerAddress: URL {
        URL(string: "http://\(host):\(port)/")!
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
    SettingsView(serverAddress: .constant(URL(string: "http://localhost:8888")!))
}
