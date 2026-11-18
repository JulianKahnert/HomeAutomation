//
//  RoomsFeature.swift
//  ControllerFeatures
//
//  Rooms with recorded device history
//

import ComposableArchitecture
import Foundation
import HAModels
import Sharing
import SwiftUI

@Reducer
enum RoomsPath {
    case room(RoomFeature)
    case entity(EntityHistoryDetailFeature)
}

extension RoomsPath.State: Equatable, Sendable {}
extension RoomsPath.Action: Sendable {}

@Reducer
struct RoomsFeature: Sendable {

    // MARK: - State

    @ObservableState
    struct State: Equatable, Sendable {
        var entities: [EntityInfo] = []
        var isLoading = false
        var searchText = ""
        var path = StackState<RoomsPath.State>()
        @Presents var alert: AlertState<Action.Alert>?

        /// Rooms whose name or devices match the search, each with all of its devices.
        var rooms: [(placeId: String, entities: [EntityInfo])] {
            Dictionary(grouping: entities, by: \.entityId.placeId)
                .filter { placeId, entities in
                    searchText.isEmpty
                        || placeId.localizedStandardContains(searchText)
                        || entities.contains { $0.entityId.name.localizedStandardContains(searchText) }
                }
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
        case path(StackActionOf<RoomsPath>)
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

            case .path:
                return .none

            case .alert:
                return .none
            }
        }
        .forEach(\.path, action: \.path)
        .ifLet(\.$alert, action: \.alert)
    }
}

struct RoomsView: View {
    @Bindable var store: StoreOf<RoomsFeature>

    var body: some View {
        NavigationStack(path: $store.scope(\.path, action: \.path)) {
            List {
                ForEach(store.rooms, id: \.placeId) { room in
                    NavigationLink(state: RoomsPath.State.room(RoomFeature.State(placeId: room.placeId, entities: room.entities))) {
                        LabeledContent(room.placeId) {
                            // `Text` takes a LocalizedStringKey, which is what parses the inflect markup.
                            Text("^[\(room.entities.count) device](inflect: true)")
                        }
                    }
                }
            }
            .searchable(text: $store.searchText, prompt: "Search rooms and devices")
            .navigationTitle("Rooms")
            .refreshable {
                store.send(.refresh)
            }
            .onAppear {
                store.send(.onAppear)
            }
            .overlay {
                if store.isLoading && store.entities.isEmpty {
                    ProgressView()
                } else if store.entities.isEmpty {
                    ContentUnavailableView(
                        "No Rooms",
                        systemImage: "square.grid.2x2",
                        description: Text("Rooms with recorded device history appear here.")
                    )
                }
            }
            .alert($store.scope(\.$alert, action: \.alert))
        } destination: { pathStore in
            switch pathStore.case {
            case let .room(roomStore):
                RoomView(store: roomStore)
            case let .entity(entityStore):
                EntityHistoryDetailView(store: entityStore)
                    .navigationTitle(entityStore.entity.displayName)
            }
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
