//
//  AppFeature.swift
//  ControllerFeatures
//
//  Root app feature coordinating all tabs
//

import ComposableArchitecture
import Foundation
import HAModels
import SwiftUI

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

        case binding(BindingAction<State>)
    }

    // MARK: - Dependencies

    @Dependency(\.liveActivity) var liveActivity
    @Dependency(\.pushNotification) var pushNotification
    @Dependency(\.serverClient) var serverClient

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
                    async let monitoring: Void = send(.startMonitoringLiveActivities)
                    async let refresh: Void = send(.refreshWindowStates)
                    _ = await (monitoring, refresh)
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
                return .run { _ in
                    try await serverClient.registerDevice(token)
                }

            // MARK: - Background Tasks

            case .refreshWindowStates:
                return .run { send in
                    await send(.settings(.refreshWindowStates))
                }

            case .binding:
                return .none
            }
        }
    }
}

struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>

    var body: some View {
        TabView(selection: $store.selectedTab) {
            Tab(
                AppFeature.Tab.automations.title,
                systemImage: AppFeature.Tab.automations.systemImage,
                value: AppFeature.Tab.automations
            ) {
                AutomationsView(
                    store: store.scope(
                        state: \.automations,
                        action: \.automations
                    )
                )
            }

            Tab(
                AppFeature.Tab.actions.title,
                systemImage: AppFeature.Tab.actions.systemImage,
                value: AppFeature.Tab.actions
            ) {
                ActionsView(
                    store: store.scope(
                        state: \.actions,
                        action: \.actions
                    )
                )
            }

            Tab(
                AppFeature.Tab.settings.title,
                systemImage: AppFeature.Tab.settings.systemImage,
                value: AppFeature.Tab.settings
            ) {
                SettingsView(
                    store: store.scope(
                        state: \.settings,
                        action: \.settings
                    )
                )
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .onAppear {
            store.send(.onAppear)
        }
    }
}

#Preview {
    AppView(
        store: Store(initialState: AppFeature.State()) {
            AppFeature()
        }
    )
}
