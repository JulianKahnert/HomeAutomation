//
//  SettingsFeature.swift
//  ControllerFeatures
//
//  Feature for app settings management
//

import ComposableArchitecture
import Foundation
import HAModels
import Logging
import Sharing
import SwiftUI

@Reducer
enum SettingsPath {
    case logs(LogViewerFeature)
}

extension SettingsPath.State: Equatable, Sendable {}
extension SettingsPath.Action: Sendable {}

@Reducer
struct SettingsFeature: Sendable {

    private static let logger = Logger(label: "SettingsFeature")

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
        var serverURLString: String = ""
        var serverAuthToken: String = ""

        var path = StackState<SettingsPath.State>()
    }

    // MARK: - Action

    enum Action: Sendable, BindableAction {
        case onAppear
        case editServerURL
        case saveServerURL
        case cancelEditServerURL
        case toggleLiveActivities(Bool)
        case refreshWindowStates
        case windowStatesResponse(Result<WindowContentState, Error>)
        case requestPushAuthorization
        case dismissError
        case path(StackActionOf<SettingsPath>)
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

            case .editServerURL:
                state.isEditingServerURL = true
                // Remove trailing slash if present for cleaner editing
                state.serverURLString = state.serverURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                state.serverAuthToken = state.authToken
                return .none

            case .saveServerURL:
                state.isEditingServerURL = false
                // Parse and validate the URL
                var urlString = state.serverURLString.trimmingCharacters(in: .whitespaces)

                // Add trailing slash if not present (required for proper URL handling)
                if !urlString.hasSuffix("/") {
                    urlString += "/"
                }

                if let url = URL(string: urlString) {
                    state.$serverURL.withLock { $0 = url }
                }
                state.$authToken.withLock { $0 = state.serverAuthToken }
                return .none

            case .cancelEditServerURL:
                state.isEditingServerURL = false
                return .none

            case let .toggleLiveActivities(enabled):
                Self.logger.info("Live Activities toggled: \(enabled)")
                state.$liveActivitiesEnabled.withLock { $0 = enabled }
                if !enabled {
                    Self.logger.info("Stopping all Live Activities (user disabled)")
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
                        Result { try await serverClient.getWindowContentState() }
                    ))
                }

            case let .windowStatesResponse(.success(contentState)):
                state.isLoadingWindowStates = false
                state.windowContentState = contentState
                Self.logger.info("Received open windows", metadata: ["openCount": "\(contentState.openCount)"])

                if state.liveActivitiesEnabled {
                    return .run { _ in
                        let hasActive = await liveActivity.hasActiveActivities()

                        if contentState.windows.isEmpty {
                            Self.logger.info("No open windows, stopping Live Activities")
                            await liveActivity.stopActivity()
                        } else if hasActive {
                            Self.logger.info("Updating existing Live Activity", metadata: ["openCount": "\(contentState.openCount)"])
                            await liveActivity.updateActivity(contentState)
                        } else {
                            Self.logger.info("No active Live Activity, starting a new one", metadata: ["openCount": "\(contentState.openCount)"])
                            try await liveActivity.startActivity(contentState)
                        }
                    } catch: { error, _ in
                        Self.logger.error("Failed to update the Live Activity", metadata: ["error": "\(error)"])
                    }
                } else {
                    Self.logger.debug("Live Activities disabled, skipping activity update")
                    return .none
                }

            case let .windowStatesResponse(.failure(error)):
                state.isLoadingWindowStates = false
                state.error = String(localized: "Failed to load window states: \(error.localizedDescription)", bundle: .module)
                Self.logger.error("Failed to load window states", metadata: ["error": "\(error)"])

                guard state.liveActivitiesEnabled else { return .none }
                return .run { _ in
                    if await liveActivity.hasActiveActivities() {
                        await liveActivity.updateActivity(.empty)
                    }
                }

            case .requestPushAuthorization:
                return .run { _ in
                    try await pushNotification.requestAuthorization()
                } catch: { error, _ in
                    Self.logger.error("Push authorization failed", metadata: ["error": "\(error)"])
                }

            case .dismissError:
                state.error = nil
                return .none

            case .path:
                return .none

            case .binding:
                return .none
            }
        }
        .forEach(\.path, action: \.path)
    }
}

struct SettingsView: View {
    @Bindable var store: StoreOf<SettingsFeature>

    var body: some View {
        NavigationStack(path: $store.scope(\.path, action: \.path)) {
            Form {
                Section {
                    serverConfigSection
                } header: {
                    Text("Server Configuration", bundle: .module)
                } footer: {
                    Text("FlowKit server endpoint", bundle: .module)
                }

                #if os(iOS)
                Section {
                    liveActivitiesSection
                } header: {
                    Text("Live Activities", bundle: .module)
                } footer: {
                    Text("Show window states in Dynamic Island and Lock Screen", bundle: .module)
                }
                #endif

                Section(String(localized: "Diagnostics", bundle: .module)) {
                    NavigationLink(state: SettingsPath.State.logs(LogViewerFeature.State())) {
                        Label(String(localized: "App Logs", bundle: .module), systemImage: "doc.text.magnifyingglass")
                    }
                }
            }
            .navigationTitle(String(localized: "Settings", bundle: .module))
            .refreshable {
                store.send(.refreshWindowStates)
            }
            .onAppear {
                store.send(.onAppear)
            }
        } destination: { pathStore in
            switch pathStore.case {
            case let .logs(logStore):
                LogViewerFeatureView(store: logStore)
            }
        }
    }

    @ViewBuilder
    private var serverConfigSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Server URL", bundle: .module)
                    .font(.headline)
                Spacer()
                Button {
                    store.send(.editServerURL)
                } label: {
                    Text("Edit", bundle: .module)
                }
            }

            Text(store.serverURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if store.isEditingServerURL {
            TextField(String(localized: "Server URL (e.g. http://localhost:8080)", bundle: .module), text: $store.serverURLString)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif

            SecureField(String(localized: "Auth Token", bundle: .module), text: $store.serverAuthToken)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif

            Button(String(localized: "Save", bundle: .module)) {
                store.send(.saveServerURL)
            }
            .buttonStyle(.borderedProminent)

            Button(String(localized: "Cancel", bundle: .module)) {
                store.send(.cancelEditServerURL)
            }
        }
    }

    #if os(iOS)
    @ViewBuilder
    private var liveActivitiesSection: some View {
        Toggle(String(localized: "Enable Live Activities", bundle: .module), isOn: Binding(
            get: { store.liveActivitiesEnabled },
            set: { store.send(.toggleLiveActivities($0)) }
        ))
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
