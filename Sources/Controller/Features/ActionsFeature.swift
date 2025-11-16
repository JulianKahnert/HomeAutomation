//
//  ActionsFeature.swift
//  ControllerFeatures
//
//  Feature for viewing and managing action log
//

import ComposableArchitecture
import Foundation
import HAModels
import Sharing

@Reducer
public struct ActionsFeature: Sendable {

    // MARK: - State

    @ObservableState
    public struct State: Equatable, Sendable {
        public var actions: [ActionLogItem] = []
        public var isLoading: Bool = false
        public var error: String?
        public var limit: Int = 50
        public var searchText: String = ""

        public var filteredActions: [ActionLogItem] {
            guard !searchText.isEmpty else {
                return actions
            }

            let searchLowercased = searchText.localizedLowercase
            return actions.filter { item in
                item.searchableText.contains(searchLowercased)
            }
        }

        public init(
            actions: [ActionLogItem] = [],
            isLoading: Bool = false,
            error: String? = nil,
            limit: Int = 50,
            searchText: String = ""
        ) {
            self.actions = actions
            self.isLoading = isLoading
            self.error = error
            self.limit = limit
            self.searchText = searchText
        }
    }

    // MARK: - Action

    public enum Action: Sendable, BindableAction {
        case onAppear
        case refresh
        case actionsResponse(Result<[ActionLogItem], Error>)
        case clearActions
        case clearActionsResponse(Result<Void, Error>)
        case setLimit(Int)
        case dismissError
        case binding(BindingAction<State>)
    }

    // MARK: - Dependencies

    @Dependency(\.flowKitClient) var flowKitClient

    // MARK: - Body

    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .run { send in
                    await send(.refresh)
                }

            case .refresh:
                state.isLoading = true
                state.error = nil
                let limit = state.limit
                return .run { send in
                    await send(.actionsResponse(
                        Result { try await flowKitClient.getActions(limit) }
                    ))
                }

            case let .actionsResponse(.success(actions)):
                state.isLoading = false
                state.actions = actions
                return .none

            case let .actionsResponse(.failure(error)):
                state.isLoading = false
                state.error = "Failed to load actions: \(error.localizedDescription)"
                return .none

            case .clearActions:
                state.error = nil
                return .run { send in
                    await send(.clearActionsResponse(
                        Result { try await flowKitClient.clearActions() }
                    ))
                }

            case .clearActionsResponse(.success):
                // Refresh the list after clearing
                return .run { send in
                    await send(.refresh)
                }

            case let .clearActionsResponse(.failure(error)):
                state.error = "Failed to clear actions: \(error.localizedDescription)"
                return .none

            case let .setLimit(limit):
                state.limit = limit
                return .run { send in
                    await send(.refresh)
                }

            case .dismissError:
                state.error = nil
                return .none

            case .binding:
                return .none
            }
        }
    }
}
