//
//  AppFeature.swift
//  ControllerFeatures
//
//  Root app feature coordinating all tabs
//

import ComposableArchitecture
import Foundation
import HAModels

@Reducer
public struct AppFeature: Sendable {

    // MARK: - State

    @ObservableState
    public struct State: Equatable, Sendable {
        public var selectedTab: Tab = .automations
        public var automations = AutomationsFeature.State()
        public var actions = ActionsFeature.State()
        public var settings = SettingsFeature.State()

        public init(
            selectedTab: Tab = .automations,
            automations: AutomationsFeature.State = .init(),
            actions: ActionsFeature.State = .init(),
            settings: SettingsFeature.State = .init()
        ) {
            self.selectedTab = selectedTab
            self.automations = automations
            self.actions = actions
            self.settings = settings
        }
    }

    // MARK: - Tab

    public enum Tab: Sendable, Equatable, CaseIterable {
        case automations
        case actions
        case settings

        public var title: String {
            switch self {
            case .automations: return "Automations"
            case .actions: return "Actions"
            case .settings: return "Settings"
            }
        }

        public var systemImage: String {
            switch self {
            case .automations: return "lamp.floor"
            case .actions: return "list.bullet.clipboard"
            case .settings: return "gear"
            }
        }
    }

    // MARK: - Action

    public enum Action: Sendable {
        case onAppear
        case selectedTabChanged(Tab)
        case automations(AutomationsFeature.Action)
        case actions(ActionsFeature.Action)
        case settings(SettingsFeature.Action)

        // Live Activities
        case startMonitoringLiveActivities
        case stopMonitoringLiveActivities
        case liveActivityPushTokenReceived(Data)
        case windowStatesUpdated([WindowContentState.WindowState])

        // Push Notifications
        case startMonitoringPushNotifications
        case stopMonitoringPushNotifications
        case deviceTokenReceived(Data)
        case registerDeviceToken(Data, String?)

        // Background tasks
        case refreshWindowStates
        case syncComplete
    }

    // MARK: - Dependencies

    @Dependency(\.liveActivity) var liveActivity
    @Dependency(\.pushNotification) var pushNotification
    @Dependency(\.flowKitClient) var flowKitClient

    // MARK: - Body

    public var body: some ReducerOf<Self> {
        Scope(state: \.automations, action: \.automations) {
            AutomationsFeature()
        }

        Scope(state: \.actions, action: \.actions) {
            ActionsFeature()
        }

        Scope(state: \.settings, action: \.settings) {
            SettingsFeature()
        }

        Reduce { state, action in
            switch action {
            case .onAppear:
                return .run { send in
                    await send(.startMonitoringPushNotifications)
                    await send(.startMonitoringLiveActivities)
                    await send(.refreshWindowStates)
                }

            case let .selectedTabChanged(tab):
                state.selectedTab = tab
                return .none

            case .automations:
                return .none

            case .actions:
                return .none

            case .settings:
                return .none

            // MARK: - Live Activities

            case .startMonitoringLiveActivities:
                guard state.settings.liveActivitiesEnabled else {
                    return .none
                }

                return .run { send in
                    // Monitor push tokens for Live Activities
                    for await token in await liveActivity.pushTokenUpdates() {
                        await send(.liveActivityPushTokenReceived(token))
                    }
                }

            case .stopMonitoringLiveActivities:
                return .run { _ in
                    await liveActivity.stopActivity()
                }

            case let .liveActivityPushTokenReceived(token):
                return .run { send in
                    await send(.registerDeviceToken(token, "live_activity"))
                }

            case let .windowStatesUpdated(windowStates):
                state.settings.windowContentState = WindowContentState(windowStates: windowStates)

                // Start or update Live Activity if enabled
                if state.settings.liveActivitiesEnabled, !windowStates.isEmpty {
                    return .run { _ in
                        let hasActive = await liveActivity.hasActiveActivities()
                        if hasActive {
                            await liveActivity.updateActivity(windowStates)
                        } else {
                            try await liveActivity.startActivity(windowStates)
                        }
                    } catch: { _, _ in
                        // Ignore errors for now
                    }
                }
                return .none

            // MARK: - Push Notifications

            case .startMonitoringPushNotifications:
                return .run { send in
                    // Monitor device tokens
                    for await token in await pushNotification.deviceTokenUpdates() {
                        await send(.deviceTokenReceived(token))
                    }
                }

            case .stopMonitoringPushNotifications:
                return .run { _ in
                    await pushNotification.unregister()
                }

            case let .deviceTokenReceived(token):
                return .run { send in
                    await send(.registerDeviceToken(token, nil))
                }

            case let .registerDeviceToken(token, activityType):
                let tokenString = token.map { String(format: "%02x", $0) }.joined()
                let deviceName = "iOS Device" // TODO: Get actual device name

                return .run { send in
                    try await flowKitClient.registerDevice(
                        deviceName,
                        tokenString,
                        .apns,
                        activityType
                    )
                    await send(.syncComplete)
                } catch: { _, _ in
                    // Ignore registration errors for now
                }

            // MARK: - Background Tasks

            case .refreshWindowStates:
                return .run { send in
                    await send(.settings(.refreshWindowStates))
                }

            case .syncComplete:
                return .none
            }
        }
    }
}
