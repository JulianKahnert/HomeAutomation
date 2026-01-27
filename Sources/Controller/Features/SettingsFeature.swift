//
//  SettingsFeature.swift
//  ControllerFeatures
//
//  Feature for app settings management
//

import ComposableArchitecture
import Foundation
import HAModels
import Sharing
import SwiftUI

@Reducer
struct SettingsFeature: Sendable {

    // MARK: - State

    @ObservableState
    struct State: Equatable, Sendable {
        @Shared(.serverURL) var serverURL: URL
        @Shared(.authToken) var authToken: String = ""
        @Shared(.liveActivitiesEnabled) var liveActivitiesEnabled: Bool = true
        var windowContentState: WindowContentState?
        var isLoadingWindowStates: Bool = false
        var error: String?

        // Server URL editing state
        var isEditingServerURL: Bool = false
        var serverHost: String = "localhost"
        var serverPort: Int = 8080
        var serverAuthToken: String = ""

        // Push notification state
        var isPushAuthorized: Bool = false
        var deviceToken: Data?
    }

    // MARK: - Action

    enum Action: Sendable, BindableAction {
        case onAppear
        case setServerURL(URL)
        case editServerURL
        case saveServerURL
        case cancelEditServerURL
        case toggleLiveActivities(Bool)
        case refreshWindowStates
        case windowStatesResponse(Result<[WindowContentState.WindowState], Error>)
        case requestPushAuthorization
        case dismissError
        case binding(BindingAction<State>)
    }

    // MARK: - Dependencies

    @Dependency(\.serverClient) var serverClient
    @Dependency(\.liveActivity) var liveActivity
    @Dependency(\.pushNotification) var pushNotification

    // MARK: - Body

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .run { send in
                    await send(.requestPushAuthorization)
                    await send(.refreshWindowStates)
                }

            case let .setServerURL(url):
                state.$serverURL.withLock { $0 = url }
                return .none

            case .editServerURL:
                state.isEditingServerURL = true
                state.serverHost = state.serverURL.host() ?? "localhost"
                state.serverPort = state.serverURL.port ?? 8080
                state.serverAuthToken = state.authToken
                return .none

            case .saveServerURL:
                state.isEditingServerURL = false
                let urlString = "http://\(state.serverHost):\(state.serverPort)/"
                if let url = URL(string: urlString) {
                    state.$serverURL.withLock { $0 = url }
                }
                state.$authToken.withLock { $0 = state.serverAuthToken }
                return .none

            case .cancelEditServerURL:
                state.isEditingServerURL = false
                return .none

            case let .toggleLiveActivities(enabled):
                state.$liveActivitiesEnabled.withLock { $0 = enabled }
                if !enabled {
                    // Stop any running activities when disabled
                    return .run { _ in
                        await liveActivity.stopActivity()
                    }
                }
                return .none

            case .refreshWindowStates:
                state.isLoadingWindowStates = true
                state.error = nil
                return .run { send in
                    await send(.windowStatesResponse(
                        Result { try await serverClient.getWindowStates() }
                    ))
                }

            case let .windowStatesResponse(.success(windowStates)):
                state.isLoadingWindowStates = false
                state.windowContentState = WindowContentState(windowStates: windowStates)

                if state.liveActivitiesEnabled {
                    return .run { _ in
                        let hasActive = await liveActivity.hasActiveActivities()

                        // Check empty first to ensure we stop activities when no windows are open,
                        // even if an activity is currently running (prevents showing empty live activities)
                        if windowStates.isEmpty {
                            await liveActivity.stopActivity()
                        } else if hasActive {
                            await liveActivity.updateActivity(windowStates)
                        } else {
                            try await liveActivity.startActivity(windowStates)
                        }
                    }
                } else {
                    return .none
                }

            case let .windowStatesResponse(.failure(error)):
                state.isLoadingWindowStates = false
                state.error = "Failed to load window states: \(error.localizedDescription)"

                return .run { _ in
                    await liveActivity.updateActivity([])
                }

            case .requestPushAuthorization:
                return .run { _ in
                    try await pushNotification.requestAuthorization()
                }

            case .dismissError:
                state.error = nil
                return .none

            case .binding:
                return .none
            }
        }
    }
}

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
            SecureField("Auth Token", text: $store.serverAuthToken)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif

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

#Preview {
    SettingsView(
        store: Store(initialState: SettingsFeature.State()) {
            SettingsFeature()
        }
    )
}
