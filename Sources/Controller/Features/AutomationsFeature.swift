//
//  AutomationsFeature.swift
//  ControllerFeatures
//
//  Feature for managing home automations
//

import ComposableArchitecture
import Foundation
import HAModels
import Sharing

@Reducer
struct AutomationsFeature: Sendable {

    // MARK: - State

    @ObservableState
    struct State: Equatable, Sendable {
        var automations: [AutomationInfo] = []
        var isLoading: Bool = false
        var selectedAutomationIndex: Int?
        var error: String?

        var runningAutomations: [AutomationInfo] {
            automations.filter(\.isRunning)
        }

        var inactiveAutomations: [AutomationInfo] {
            automations.filter { !$0.isRunning }
        }
    }

    // MARK: - Action

    enum Action: Sendable {
        case onAppear
        case refresh
        case automationsResponse(Result<[AutomationInfo], Error>)
        case selectAutomation(Int?)
        case activateAutomation(String)
        case deactivateAutomation(String)
        case stopAutomation(String)
        case automationOperationResponse(Result<Void, Error>)
        case dismissError
    }

    // MARK: - Dependencies

    @Dependency(\.flowKitClient) var flowKitClient

    // MARK: - Body

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .run { send in
                    await send(.refresh)
                }

            case .refresh:
                state.isLoading = true
                state.error = nil
                return .run { send in
                    await send(.automationsResponse(
                        Result { try await flowKitClient.getAutomations() }
                    ))
                }

            case let .automationsResponse(.success(automations)):
                state.isLoading = false
                state.automations = automations
                return .none

            case let .automationsResponse(.failure(error)):
                state.isLoading = false
                state.error = "Failed to load automations: \(error.localizedDescription)"
                return .none

            case let .selectAutomation(index):
                state.selectedAutomationIndex = index
                return .none

            case let .activateAutomation(name):
                state.error = nil
                return .run { send in
                    await send(.automationOperationResponse(
                        Result { try await flowKitClient.activate(name) }
                    ))
                }

            case let .deactivateAutomation(name):
                state.error = nil
                return .run { send in
                    await send(.automationOperationResponse(
                        Result { try await flowKitClient.deactivate(name) }
                    ))
                }

            case let .stopAutomation(name):
                state.error = nil
                return .run { send in
                    await send(.automationOperationResponse(
                        Result { try await flowKitClient.stop(name) }
                    ))
                }

            case .automationOperationResponse(.success):
                // Refresh the list after a successful operation
                return .run { send in
                    await send(.refresh)
                }

            case let .automationOperationResponse(.failure(error)):
                state.error = "Operation failed: \(error.localizedDescription)"
                return .none

            case .dismissError:
                state.error = nil
                return .none
            }
        }
    }
}
