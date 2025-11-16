//
//  SettingsView.swift
//  ControllerFeatures
//
//  TCA-based settings view
//

import ComposableArchitecture
import HAModels
import SwiftUI

public struct SettingsView: View {
    @Bindable public var store: StoreOf<SettingsFeature>

    public init(store: StoreOf<SettingsFeature>) {
        self.store = store
    }

    public var body: some View {
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

            Text(store.serverURL?.absoluteString ?? "Not configured")
                .font(.caption)
                .foregroundColor(.secondary)
        }

        if store.isEditingServerURL {
            TextField("Host", text: $store.serverHost)
            TextField("Port", value: $store.serverPort, format: .number)

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

        if store.liveActivitiesEnabled {
            Button("Refresh Window States") {
                store.send(.refreshWindowStates)
            }
        }
    }

    @ViewBuilder
    private func windowStatesSection(_ windowState: WindowContentState) -> some View {
        if windowState.windowStates.isEmpty {
            Text("No open windows")
                .foregroundColor(.secondary)
        } else {
            ForEach(windowState.windowStates, id: \.name) { window in
                VStack(alignment: .leading, spacing: 4) {
                    Text(window.name)
                        .font(.headline)

                    Text("Opened: \(window.opened.formatted(date: .numeric, time: .standard))")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let maxDuration = window.maxOpenDuration {
                        Text("Max duration: \(maxDuration) seconds")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
    }
    #endif
}
