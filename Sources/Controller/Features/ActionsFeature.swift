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
import SwiftUI

@Reducer
struct ActionsFeature: Sendable {

    // MARK: - State

    @ObservableState
    struct State: Equatable, Sendable {
        let limit = 1000
        var actions: [ActionLogItem] = []
        var isLoading = false
        @Presents var alert: AlertState<Action.Alert>?
        var searchText: String = ""

        var filteredActions: [ActionLogItem] {
            guard !searchText.isEmpty else {
                return actions
            }

            let searchLowercased = searchText.localizedLowercase
            return actions.filter { item in
                item.searchableText.contains(searchLowercased)
            }
        }

        var exportAsText: String {
            let header = """
            HomeKit Action Log
            Exported: \(Date().formatted(date: .long, time: .standard))
            Total Actions: \(actions.count)
            =====================================

            """

            let entries = actions.map { item in
                let status = item.hasCacheHit ? "✅ Cached" : "🆕 Fresh (no cache hit)"
                return """
                [\(item.timestamp.formatted(date: .numeric, time: .standard))] \(item.displayName)
                Action: \(item.detailDescription)
                Entity: \(item.entityId)
                Status: \(status)

                """
            }.joined(separator: "\n")

            return header + entries
        }
    }

    // MARK: - Action

    enum Action: Sendable, BindableAction {
        case onAppear
        case refresh
        case actionsResponse(Result<[ActionLogItem], Error>)
        case clearActions
        case clearActionsResponse(Result<Void, Error>)
        case alert(PresentationAction<Alert>)
        case binding(BindingAction<State>)

        enum Alert: Sendable {
            case dismissError
        }
    }

    // MARK: - Dependencies

    @Dependency(\.serverClient) var serverClient

    // MARK: - Body

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .run { send in
                    await send(.refresh)
                }

            case .refresh:
                state.isLoading = true
                state.alert = nil
                let limit = state.limit
                return .run { send in
                    await send(.actionsResponse(
                        Result { try await serverClient.getActions(limit) }
                    ))
                }

            case let .actionsResponse(.success(actions)):
                state.isLoading = false
                state.actions = actions
                return .none

            case let .actionsResponse(.failure(error)):
                state.isLoading = false
                state.alert = AlertState {
                    TextState("Error")
                } actions: {
                    ButtonState(action: .dismissError) {
                        TextState("OK")
                    }
                } message: {
                    TextState("Failed to load actions: \(error.localizedDescription)")
                }
                return .none

            case .clearActions:
                state.alert = nil
                return .run { send in
                    await send(.clearActionsResponse(
                        Result { try await serverClient.clearActions() }
                    ))
                }

            case .clearActionsResponse(.success):
                // Refresh the list after clearing
                return .run { send in
                    await send(.refresh)
                }

            case let .clearActionsResponse(.failure(error)):
                state.alert = AlertState {
                    TextState("Error")
                } actions: {
                    ButtonState(action: .dismissError) {
                        TextState("OK")
                    }
                } message: {
                    TextState("Failed to clear actions: \(error.localizedDescription)")
                }
                return .none

            case .alert:
                return .none

            case .binding:
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
    }
}

struct ActionsView: View {
    @Bindable var store: StoreOf<ActionsFeature>

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.filteredActions) { item in
                    actionRow(item)
                }
            }
            .searchable(
                text: $store.searchText,
                prompt: "Search actions..."
            )
            .navigationTitle("Actions")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        store.send(.refresh)
                    } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                    .disabled(store.isLoading)
                }

                ToolbarItem(placement: .secondaryAction) {
                    ShareLink(
                        item: store.exportAsText,
                        preview: SharePreview(
                            "HomeKit_Actions_\(Date().ISO8601Format()).txt",
                            image: Image(systemName: "doc.text")
                        )
                    )
                    .disabled(store.actions.isEmpty)
                }

                ToolbarItem(placement: .secondaryAction) {
                    Button(role: .destructive) {
                        store.send(.clearActions)
                    } label: {
                        Label("Clear All", systemImage: "trash")
                    }
                    .disabled(store.actions.isEmpty || store.isLoading)
                }
            }
            .refreshable {
                store.send(.refresh)
            }
            .onAppear {
                store.send(.onAppear)
            }
            .overlay {
                if store.isLoading && store.actions.isEmpty {
                    ProgressView()
                } else if store.actions.isEmpty && !store.isLoading {
                    ContentUnavailableView(
                        "No Actions",
                        systemImage: "list.bullet.clipboard",
                        description: Text("Actions will appear here")
                    )
                }
            }
            .alert(store: store.scope(state: \.$alert, action: \.alert))
        }
    }

    @ViewBuilder
    private func actionRow(_ item: ActionLogItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Action name and entity
            Text(item.displayName)
                .font(.headline)

            // Detailed action description with cache indicator
            HStack(spacing: 4) {
                Image(systemName: "internaldrive")
                    .opacity(item.hasCacheHit ? 1 : 0)
                Text(item.detailDescription)
                    .font(.body)
            }
            .foregroundColor(item.hasCacheHit ? Color.yellow : nil)

            // Timestamp
            Text(item.timestamp.formatted(date: .numeric, time: .standard))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    ActionsView(
        store: Store(initialState: ActionsFeature.State()) {
            ActionsFeature()
        }
    )
}
