//
//  AppFeature.swift
//  ControllerFeatures
//
//  Root app feature coordinating all tabs
//

import ComposableArchitecture
import Foundation

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
        case selectedTabChanged(Tab)
        case automations(AutomationsFeature.Action)
        case actions(ActionsFeature.Action)
        case settings(SettingsFeature.Action)
    }

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
            case let .selectedTabChanged(tab):
                state.selectedTab = tab
                return .none

            case .automations:
                return .none

            case .actions:
                return .none

            case .settings:
                return .none
            }
        }
    }
}
