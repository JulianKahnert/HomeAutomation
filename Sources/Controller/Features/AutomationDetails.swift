//
//  AutomationDetails.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 19.11.25.
//

import ComposableArchitecture
import Foundation
import HAModels
import Sharing
import SwiftUI

@Reducer
struct AutomationDetails: Sendable {

    // MARK: - State

    @ObservableState
    struct State: Equatable, Sendable {
        @Shared var automation: AutomationInfo
        var isLoading = false
    }

    enum Action: Sendable {
        case stopAutomation
        case updateIsActive(Bool)
        case updateIsLoading(Bool)
    }

    @Dependency(\.serverClient) var serverClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .stopAutomation:
                return .none

            case .updateIsActive(let isActive):
                state.$automation.withLock { $0.isActive = isActive }
                // TODO: use client here
                return .none

            case .updateIsLoading(let isLoading):
                state.isLoading = isLoading
                return .none

//            case let .activateAutomation(name):
//                state.error = nil
//                return .run { send in
//                    await send(.automationOperationResponse(
//                        Result { try await flowKitClient.activate(name) }
//                    ))
//                }
//
//            case let .deactivateAutomation(name):
//                state.error = nil
//                return .run { send in
//                    await send(.automationOperationResponse(
//                        Result { try await flowKitClient.deactivate(name) }
//                    ))
//                }
//
//            case let .stopAutomation(name):
//                state.error = nil
//                return .run { send in
//                    await send(.automationOperationResponse(
//                        Result { try await flowKitClient.stop(name) }
//                    ))
//                }

            }
        }
    }
}

struct AutomationDetailView: View {
    @Bindable var store: StoreOf<AutomationDetails>

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Is Running")
                    Spacer()
                    Image(systemName: "circle.fill")
                        .foregroundStyle(store.automation.isRunning ? Color.green : Color.gray.opacity(0.3))
                }
            }

            Section {
                Toggle("Is Active", isOn: Binding(
                    get: { store.automation.isActive },
                    set: { value in
                        store.send(.updateIsActive(value))
                    }
                ))
                .disabled(store.isLoading)
                .overlay {
                    if store.isLoading {
                        ProgressView()
                    }
                }
            }

            Section {
                Button("Stop Automation") {
                    store.send(.stopAutomation)
                }
            }
        }
        // TODO: da wo es angezeigt wird
        .navigationTitle(store.automation.name)
    }
}

#Preview {
    AutomationDetailView(
        store: Store(
            initialState: AutomationDetails.State(
                automation: Shared(value: AutomationInfo(
                    name: "Test Automation",
                    isActive: true,
                    isRunning: true
                ))
            )
        ) {
            AutomationDetails()
        }
    )
}
