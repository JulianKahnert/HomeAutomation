//
//  RoomsFeature.swift
//  ControllerFeatures
//
//  Entities grouped by room
//

import ComposableArchitecture
import Foundation
import HAModels
import Sharing
import SwiftUI

@Reducer
struct RoomsFeature: Sendable {

    // MARK: - State

    @ObservableState
    struct State: Equatable, Sendable {
        var entities: [EntityInfo] = []
        var isLoading = false
        var searchText = ""
        var selectedEntityId: String?
        @Presents var selectedEntityDetail: EntityHistoryDetailFeature.State?
        @Presents var alert: AlertState<Action.Alert>?

        var filteredEntities: [EntityInfo] {
            guard !searchText.isEmpty else {
                return entities
            }

            let searchLowercased = searchText.localizedLowercase
            return entities.filter { entity in
                entity.displayName.localizedLowercase.contains(searchLowercased) ||
                entity.formattedCharacteristicDisplayName.localizedLowercase.contains(searchLowercased)
            }
        }

        var rooms: [(placeId: String, entities: [EntityInfo])] {
            Dictionary(grouping: filteredEntities, by: \.entityId.placeId)
                .sorted { $0.key < $1.key }
                .map { ($0.key, $0.value) }
        }
    }

    // MARK: - Action

    enum Action: Sendable, BindableAction {
        case onAppear
        case refresh
        case entitiesResponse(Result<[EntityInfo], Error>)
        case binding(BindingAction<State>)
        case selectedEntityDetail(PresentationAction<EntityHistoryDetailFeature.Action>)
        case alert(PresentationAction<Alert>)

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
            case .binding(\.selectedEntityId):
                if let selectedEntityId = state.selectedEntityId,
                   let entity = state.entities.first(where: { $0.id == selectedEntityId }) {
                    state.selectedEntityDetail = .init(entity: entity)
                } else {
                    state.selectedEntityDetail = nil
                }
                return .none

            case .binding:
                return .none

            case .onAppear:
                return .run { send in
                    await send(.refresh)
                }

            case .refresh:
                state.isLoading = true
                state.alert = nil
                return .run { send in
                    do {
                        let entities = try await serverClient.getEntityIdsWithHistory()
                        await send(.entitiesResponse(.success(entities)))
                    } catch {
                        await send(.entitiesResponse(.failure(error)))
                    }
                }

            case let .entitiesResponse(.success(entities)):
                state.isLoading = false
                state.entities = entities.sorted { $0.entityId.name < $1.entityId.name }
                return .none

            case let .entitiesResponse(.failure(error)):
                state.isLoading = false
                state.alert = AlertState {
                    TextState("Error")
                } actions: {
                    ButtonState(action: .dismissError) {
                        TextState("OK")
                    }
                } message: {
                    TextState("Failed to load entities: \(error.localizedDescription)")
                }
                return .none

            case .selectedEntityDetail:
                return .none

            case .alert:
                return .none
            }
        }
        .ifLet(\.$selectedEntityDetail, action: \.selectedEntityDetail) {
            EntityHistoryDetailFeature()
        }
        .ifLet(\.$alert, action: \.alert)
    }
}

struct RoomsView: View {
    @Bindable var store: StoreOf<RoomsFeature>

    var body: some View {
        NavigationStack {
            contentView
                .navigationTitle("Rooms")
                .navigationDestination(
                    item: $store.scope(state: \.selectedEntityDetail, action: \.selectedEntityDetail)
                ) { detailStore in
                    EntityHistoryDetailView(store: detailStore)
                        .navigationTitle(detailStore.entity.displayName)
                }
                .sensoryFeedback(.selection, trigger: store.selectedEntityId)
                .refreshable {
                    store.send(.refresh)
                }
                .onAppear {
                    store.send(.onAppear)
                }
                .overlay {
                    if store.isLoading && store.entities.isEmpty {
                        ProgressView()
                    }
                }
                .alert($store.scope(state: \.alert, action: \.alert))
        }
    }

    @ViewBuilder
    private var contentView: some View {
        Group {
            if store.entities.isEmpty && !store.isLoading {
                ContentUnavailableView(
                    "No Entities",
                    systemImage: "square.grid.2x2",
                    description: Text("Devices with recorded history appear here.")
                )
            } else {
                List(selection: $store.selectedEntityId) {
                    ForEach(store.rooms, id: \.placeId) { room in
                        Section(room.placeId) {
                            ForEach(room.entities) { entity in
                                entityRow(entity)
                                    .tag(entity.id)
                            }
                        }
                    }
                }
                .searchable(
                    text: $store.searchText,
                    prompt: "Search devices..."
                )
            }
        }
    }

    @ViewBuilder
    private func entityRow(_ entity: EntityInfo) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(entity.entityId.name)
                Text(entity.formattedCharacteristicDisplayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: entity.entityId.characteristicType.systemImage)
        }
    }
}

#Preview {
    RoomsView(
        store: Store(initialState: RoomsFeature.State()) {
            RoomsFeature()
        }
    )
}
