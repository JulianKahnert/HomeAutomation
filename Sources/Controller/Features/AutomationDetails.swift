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
        var error: String?
    }

    enum Action: Sendable {
        case stopAutomation
        case updateIsActive(Bool)
        case isActiveOperationResponse(Result<Bool, Error>)
        case stopOperationResponse(Result<Void, Error>)
    }

    @Dependency(\.serverClient) var serverClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .stopAutomation:
                state.error = nil
                state.isLoading = true
                return .run { [name = state.automation.name] send in
                    await send(.stopOperationResponse(
                        Result { try await serverClient.stop(name) }
                    ))
                }

            case .updateIsActive(let isActive):
                state.error = nil
                state.isLoading = true
                return .run { [name = state.automation.name] send in
                    await send(.isActiveOperationResponse(
                        Result {
                            if isActive {
                                try await serverClient.activate(name)
                            } else {
                                try await serverClient.deactivate(name)
                            }
                            return isActive
                        }
                    ))
                }

            case .isActiveOperationResponse(.success(let isActive)):
                state.$automation.withLock { $0.isActive = isActive }
                state.isLoading = false
                return .none

            case let .isActiveOperationResponse(.failure(error)):
                state.isLoading = false
                state.error = "Failed to load automations: \(error.localizedDescription)"
                return .none

            case .stopOperationResponse(.success):
                state.isLoading = false
                state.$automation.withLock { $0.isRunning = false }
                return .none

            case let .stopOperationResponse(.failure(error)):
                state.isLoading = false
                state.error = "Failed to load automations: \(error.localizedDescription)"
                return .none
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
            } footer: {
                if let error = store.error {
                    Text(error)
                        .foregroundStyle(Color.red)
                }
            }
        }
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
