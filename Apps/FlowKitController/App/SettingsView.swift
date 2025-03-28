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

    @State private var host: String
    @State private var port: Int

    private var newServerAddress: URL {
        URL(string: "http://\(host):\(port)/")!
    }

    init(serverAddress: Binding<URL>) {
        self._serverAddress = serverAddress

        self.host = serverAddress.wrappedValue.host() ?? "localhost"
        self.port = serverAddress.wrappedValue.port ?? 8080
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
