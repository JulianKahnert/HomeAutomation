//
//  AppView.swift
//  ControllerFeatures
//
//  Root TCA-based app view with tab navigation
//

import ComposableArchitecture
import SwiftUI

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
