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
struct AppFeature: Sendable {

    // MARK: - State

    @ObservableState
    struct State: Equatable, Sendable {
        var selectedTab: Tab = .automations
        var automations = AutomationsFeature.State()
        var actions = ActionsFeature.State()
        var settings = SettingsFeature.State()
    }

    // MARK: - Tab

    enum Tab: Sendable, Equatable, CaseIterable {
        case automations
        case actions
        case settings

        var title: String {
            switch self {
            case .automations: return "Automations"
            case .actions: return "Actions"
            case .settings: return "Settings"
            }
        }

        var systemImage: String {
            switch self {
            case .automations: return "lamp.floor"
            case .actions: return "list.bullet.clipboard"
            case .settings: return "gear"
            }
        }
    }

    // MARK: - Action

    enum Action: Sendable, BindableAction {
        case onAppear
        case selectedTabChanged(Tab)
        case automations(AutomationsFeature.Action)
        case actions(ActionsFeature.Action)
        case settings(SettingsFeature.Action)

        // Live Activities & Push Notifications
        case startMonitoringLiveActivities
        case stopMonitoringLiveActivities
        case registerPushToken(PushToken)

        // Background tasks
        case refreshWindowStates
        case syncComplete

        case binding(BindingAction<State>)
    }

    // MARK: - Dependencies

    @Dependency(\.liveActivity) var liveActivity
    @Dependency(\.pushNotification) var pushNotification
    @Dependency(\.flowKitClient) var flowKitClient

    // MARK: - Body

    var body: some ReducerOf<Self> {
        BindingReducer()

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
                    await withTaskGroup(of: Void.self) { group in
                        group.addTask {
                            for await token in await liveActivity.pushToStartTokenUpdates() {
                                await send(.registerPushToken(token))
                            }
                        }

                        group.addTask {
                            for await token in await liveActivity.pushTokenUpdates() {
                                await send(.registerPushToken(token))
                            }
                        }
                    }
                }

            case .stopMonitoringLiveActivities:
                return .run { _ in
                    await liveActivity.stopActivity()
                }

            // MARK: - Push Notifications

            case let .registerPushToken(token):
                return .run { send in
                    try await flowKitClient.registerDevice(token)
                    await send(.syncComplete)
                }

            // MARK: - Background Tasks

            case .refreshWindowStates:
                return .run { send in
                    await send(.settings(.refreshWindowStates))
                }

            case .syncComplete:
                return .none

            case .binding:
                return .none
            }
        }
    }
}
