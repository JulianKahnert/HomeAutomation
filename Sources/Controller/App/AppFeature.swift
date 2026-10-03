//
//  AppFeature.swift
//  ControllerFeatures
//
//  Root app feature coordinating all tabs
//

import ComposableArchitecture
import Foundation
import HAModels
import Logging
import SwiftUI

@Reducer
struct AppFeature: Sendable {

    private static let logger = Logger(label: "AppFeature")

    private enum CancelID {
        case liveActivityMonitoring
    }

    // MARK: - State

    @ObservableState
    struct State: Equatable, Sendable {
        var selectedTab: Tab = .overview
        var overview = OverviewFeature.State()
        var automations = AutomationsFeature.State()
        var rooms = RoomsFeature.State()
        var settings = SettingsFeature.State()

        var openWindowsCount: Int? {
            settings.windowContentState?.windowStates.count
        }
    }

    // MARK: - Tab

    enum Tab: Sendable, Equatable, CaseIterable {
        case overview
        case automations
        case rooms
        case settings

        var title: String {
            switch self {
            case .overview: return "Overview"
            case .automations: return "Automations"
            case .rooms: return "Rooms"
            case .settings: return "Settings"
            }
        }

        var systemImage: String {
            switch self {
            case .overview: return "house"
            case .automations: return "lamp.floor"
            case .rooms: return "square.grid.2x2"
            case .settings: return "gear"
            }
        }
    }

    // MARK: - Action

    enum Action: Sendable, BindableAction {
        case selectedTabChanged(Tab)
        case overview(OverviewFeature.Action)
        case automations(AutomationsFeature.Action)
        case rooms(RoomsFeature.Action)
        case settings(SettingsFeature.Action)

        // Live Activities & Push Notifications
        case startMonitoringLiveActivities
        case stopMonitoringLiveActivities
        case registerPushToken(PushToken)
        case clearDeliveredNotifications

        // Background tasks
        case refreshWindowStates

        // Scene phase changes
        case scenePhaseChanged(old: ScenePhase, new: ScenePhase)
        case refreshAll

        case binding(BindingAction<State>)
    }

    // MARK: - Dependencies

    @Dependency(\.liveActivity) var liveActivity
    @Dependency(\.pushNotification) var pushNotification
    @Dependency(\.serverClient) var serverClient

    // MARK: - Body

    var body: some ReducerOf<Self> {
        BindingReducer()

        Scope(state: \.overview, action: \.overview) {
            OverviewFeature()
        }

        Scope(state: \.automations, action: \.automations) {
            AutomationsFeature()
        }

        Scope(state: \.rooms, action: \.rooms) {
            RoomsFeature()
        }

        Scope(state: \.settings, action: \.settings) {
            SettingsFeature()
        }

        Reduce { state, action in
            switch action {
            case let .selectedTabChanged(tab):
                state.selectedTab = tab
                return .none

            case let .overview(.delegate(.openAutomation(name))):
                state.selectedTab = .automations
                return .send(.automations(.binding(.set(\.selectedAutomationIndex, name))))

            case .overview:
                return .none

            case .automations:
                return .none

            case .rooms:
                return .none

            case .settings:
                return .none

            // MARK: - Live Activities

            case .startMonitoringLiveActivities:
                guard state.settings.liveActivitiesEnabled else {
                    Self.logger.debug("Skipping live activity monitoring (disabled)")
                    return .none
                }

                Self.logger.info("Starting live activity token monitoring")
                return .run { send in
                    await withTaskGroup(of: Void.self) { group in
                        group.addTask {
                            await liveActivity.pushToStartTokenUpdates { token in
                                await send(.registerPushToken(token))
                            }
                        }

                        group.addTask {
                            await liveActivity.pushTokenUpdates { token in
                                await send(.registerPushToken(token))
                            }
                        }
                    }
                }
                .cancellable(id: CancelID.liveActivityMonitoring, cancelInFlight: true)

            case .stopMonitoringLiveActivities:
                return .run { _ in
                    await liveActivity.stopActivity()
                }

            // MARK: - Push Notifications

            case let .registerPushToken(token):
                Self.logger.info("Registering push token: type=\(token.type)")
                return .run { _ in
                    do {
                        try await serverClient.registerDevice(token)
                        Self.logger.info("Successfully registered push token: type=\(token.type)")
                    } catch {
                        Self.logger.error("Failed to register push token: type=\(token.type), error=\(error)")
                    }
                }

            case .clearDeliveredNotifications:
                return .run { _ in
                    await pushNotification.clearDeliveredNotifications()
                }

            // MARK: - Background Tasks

            case .refreshWindowStates:
                return .run { send in
                    await send(.settings(.refreshWindowStates))
                }

            // MARK: - Scene Phase Changes

            case let .scenePhaseChanged(old: oldPhase, new: newPhase):
                Self.logger.info("Scene phase: \(oldPhase) -> \(newPhase)")

                guard newPhase == .active else {
                    return .none
                }

                // Only refresh when transitioning FROM inactive or background TO active
                guard oldPhase == .inactive || oldPhase == .background else {
                    return .none
                }

                return .send(.refreshAll)

            case .refreshAll:
                return .merge(
                    .send(.overview(.refresh)),
                    .send(.automations(.refresh)),
                    .send(.rooms(.refresh)),
                    .send(.refreshWindowStates),
                    .send(.startMonitoringLiveActivities),
                    .send(.clearDeliveredNotifications)
                )

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
                AppFeature.Tab.overview.title,
                systemImage: AppFeature.Tab.overview.systemImage,
                value: AppFeature.Tab.overview
            ) {
                OverviewView(
                    store: store.scope(state: \.overview, action: \.overview),
                    openWindows: store.settings.windowContentState?.windowStates ?? []
                )
            }
            .badge(store.openWindowsCount ?? 0)

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
                AppFeature.Tab.rooms.title,
                systemImage: AppFeature.Tab.rooms.systemImage,
                value: AppFeature.Tab.rooms
            ) {
                RoomsView(store: store.scope(state: \.rooms, action: \.rooms))
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
        .onSceneChange { oldPhase, newPhase in
            store.send(.scenePhaseChanged(old: oldPhase, new: newPhase))
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
