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

@Reducer
struct SettingsFeature: Sendable {

    // MARK: - State

    @ObservableState
    struct State: Equatable, Sendable {
        @Shared(.serverURL) var serverURL: URL
        @Shared(.liveActivitiesEnabled) var liveActivitiesEnabled: Bool = true
        var windowContentState: WindowContentState?
        var isLoadingWindowStates: Bool = false
        var error: String?

        // Server URL editing state
        var isEditingServerURL: Bool = false
        var serverHost: String = "localhost"
        var serverPort: Int = 8080

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
                return .none

            case .saveServerURL:
                state.isEditingServerURL = false
                let urlString = "http://\(state.serverHost):\(state.serverPort)/"
                if let url = URL(string: urlString) {
                    state.$serverURL.withLock { $0 = url }
                }
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
                        if hasActive {
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
