//
//  SettingsView.swift
//  ControllerFeatures
//
//  TCA-based settings view
//

import ComposableArchitecture
import HAModels
import SwiftUI

struct SettingsView: View {
    @Bindable var store: StoreOf<SettingsFeature>

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    serverConfigSection
                } header: {
                    Text("Server Configuration")
                } footer: {
                    Text("FlowKit server endpoint")
                }

                #if os(iOS)
                Section {
                    liveActivitiesSection
                } header: {
                    Text("Live Activities")
                } footer: {
                    Text("Show window states in Dynamic Island and Lock Screen")
                }

                if let windowState = store.windowContentState {
                    Section {
                        windowStatesSection(windowState)
                    } header: {
                        Text("Window States")
                    }
                }
                #endif
            }
            .navigationTitle("Settings")
            .refreshable {
                store.send(.refreshWindowStates)
            }
            .onAppear {
                store.send(.onAppear)
            }
        }
    }

    @ViewBuilder
    private var serverConfigSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Server URL")
                    .font(.headline)
                Spacer()
                Button {
                    store.send(.editServerURL)
                } label: {
                    Text("Edit")
                }
            }

            Text(store.serverURL.absoluteString)
                .font(.caption)
                .foregroundColor(.secondary)
        }

        if store.isEditingServerURL {
            TextField("Host", text: $store.serverHost)
            TextField("Port", value: $store.serverPort, format: .number.grouping(.never))

            Button("Save") {
                store.send(.saveServerURL)
            }
            .buttonStyle(.borderedProminent)

            Button("Cancel") {
                store.send(.cancelEditServerURL)
            }
        }
    }

    #if os(iOS)
    @ViewBuilder
    private var liveActivitiesSection: some View {
        Toggle("Enable Live Activities", isOn: $store.liveActivitiesEnabled)
    }

    @ViewBuilder
    private func windowStatesSection(_ windowState: WindowContentState) -> some View {
        if windowState.windowStates.isEmpty {
            Text("No open windows")
                .foregroundColor(.secondary)
        } else {
            ForEach(windowState.windowStates, id: \.name) { window in
                ProgressView(timerInterval: window.opened...window.end, countsDown: false) {
                    Text(window.name)
                }
                .tint(Date() <= window.end ? Color.accentColor : Color.red)
            }
            .listRowSeparator(.hidden)
        }
    }
    #endif
}
