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
public struct SettingsFeature: Sendable {

    // MARK: - State

    @ObservableState
    public struct State: Equatable, Sendable {
        public var serverURL: URL?
        public var liveActivitiesEnabled: Bool = true
        public var windowContentState: WindowContentState?
        public var isLoadingWindowStates: Bool = false
        public var error: String?

        // Server URL editing state
        public var isEditingServerURL: Bool = false
        public var serverHost: String = "localhost"
        public var serverPort: Int = 8080

        // Push notification state
        public var isPushAuthorized: Bool = false
        public var deviceToken: Data?

        public init(
            serverURL: URL? = URL(string: "http://localhost:8080/"),
            liveActivitiesEnabled: Bool = true,
            windowContentState: WindowContentState? = nil,
            isLoadingWindowStates: Bool = false,
            error: String? = nil,
            isEditingServerURL: Bool = false,
            serverHost: String = "localhost",
            serverPort: Int = 8080,
            isPushAuthorized: Bool = false,
            deviceToken: Data? = nil
        ) {
            self.serverURL = serverURL
            self.liveActivitiesEnabled = liveActivitiesEnabled
            self.windowContentState = windowContentState
            self.isLoadingWindowStates = isLoadingWindowStates
            self.error = error
            self.isEditingServerURL = isEditingServerURL
            self.serverHost = serverHost
            self.serverPort = serverPort
            self.isPushAuthorized = isPushAuthorized
            self.deviceToken = deviceToken
        }
    }

    // MARK: - Action

    public enum Action: Sendable, BindableAction {
        case onAppear
        case setServerURL(URL)
        case editServerURL
        case saveServerURL
        case cancelEditServerURL
        case toggleLiveActivities(Bool)
        case refreshWindowStates
        case windowStatesResponse(Result<[WindowContentState.WindowState], Error>)
        case requestPushAuthorization
        case pushAuthorizationResponse(Result<Bool, Error>)
        case registerForPushNotifications
        case checkPushAuthorizationStatus
        case pushAuthorizationStatusResponse(Bool)
        case dismissError
        case binding(BindingAction<State>)
    }

    // MARK: - Dependencies

    @Dependency(\.flowKitClient) var flowKitClient
    @Dependency(\.liveActivity) var liveActivity
    @Dependency(\.pushNotification) var pushNotification

    // MARK: - Body

    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .run { send in
                    await send(.checkPushAuthorizationStatus)
                    await send(.refreshWindowStates)
                }

            case let .setServerURL(url):
                state.serverURL = url
                return .none

            case .editServerURL:
                state.isEditingServerURL = true
                if let url = state.serverURL {
                    state.serverHost = url.host() ?? "localhost"
                    state.serverPort = url.port ?? 8080
                }
                return .none

            case .saveServerURL:
                state.isEditingServerURL = false
                let urlString = "http://\(state.serverHost):\(state.serverPort)/"
                if let url = URL(string: urlString) {
                    state.serverURL = url
                }
                return .none

            case .cancelEditServerURL:
                state.isEditingServerURL = false
                return .none

            case let .toggleLiveActivities(enabled):
                state.liveActivitiesEnabled = enabled
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
                        Result { try await flowKitClient.getWindowStates() }
                    ))
                }

            case let .windowStatesResponse(.success(windowStates)):
                state.isLoadingWindowStates = false
                state.windowContentState = WindowContentState(windowStates: windowStates)
                return .none

            case let .windowStatesResponse(.failure(error)):
                state.isLoadingWindowStates = false
                state.error = "Failed to load window states: \(error.localizedDescription)"
                return .none

            case .requestPushAuthorization:
                return .run { send in
                    await send(.pushAuthorizationResponse(
                        Result { try await pushNotification.requestAuthorization() }
                    ))
                }

            case let .pushAuthorizationResponse(.success(granted)):
                state.isPushAuthorized = granted
                if granted {
                    // Register for push notifications if authorized
                    return .run { send in
                        await send(.registerForPushNotifications)
                    }
                }
                return .none

            case let .pushAuthorizationResponse(.failure(error)):
                state.error = "Failed to authorize push notifications: \(error.localizedDescription)"
                return .none

            case .registerForPushNotifications:
                return .run { _ in
                    await pushNotification.register()
                }

            case .checkPushAuthorizationStatus:
                return .run { send in
                    let isAuthorized = await pushNotification.isAuthorized()
                    await send(.pushAuthorizationStatusResponse(isAuthorized))
                }

            case let .pushAuthorizationStatusResponse(isAuthorized):
                state.isPushAuthorized = isAuthorized
                return .none

            case .dismissError:
                state.error = nil
                return .none

            case .binding:
                return .none
            }
        }
    }
}
