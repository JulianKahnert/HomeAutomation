//
//  HeatingFeature.swift
//  ControllerFeatures
//
//  The Heizung tab: rooms with their heating automation and the detail of the selected room
//

import ComposableArchitecture
import Foundation
import HAModels

@Reducer
struct HeatingFeature: Sendable {

    /// A room with a heating automation.
    struct Room: Equatable, Sendable, Identifiable {
        let placeId: String
        let name: String
        var id: String { placeId }
    }

    private enum CancelID {
        case detail
    }

    /// The type name the server reports for `RoomHeating` automations.
    static let automationType = "RoomHeating"

    @ObservableState
    struct State: Equatable, Sendable {
        var rooms: [Room] = []
        var selectedPlaceId: String?
        var range: HeatingRange = .day
        var detail: HeatingRoomDetail?
        var isLoading = false
        /// Set when the rooms could not be loaded: the server is not reachable.
        var error: String?
        /// Set when the detail of the selected room could not be loaded.
        var detailError: String?

        var selectedRoom: Room? { rooms.first { $0.placeId == selectedPlaceId } }
    }

    enum Action: BindableAction, Sendable {
        case binding(BindingAction<State>)
        case detailResponse(Result<HeatingRoomDetail, Error>)
        case refresh
        case roomsResponse(Result<[Room], Error>)
        case selectRoom(String?)
        case task
    }

    @Dependency(\.serverClient) var serverClient

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .task, .refresh:
                state.isLoading = true
                return .run { send in
                    await send(.roomsResponse(Result { Self.rooms(in: try await serverClient.getAutomations()) }))
                }

            case let .roomsResponse(.success(rooms)):
                state.isLoading = false
                state.error = nil
                state.rooms = rooms
                if state.selectedRoom == nil {
                    state.selectedPlaceId = rooms.first?.placeId
                    state.detail = nil
                }
                return loadDetail(&state)

            case let .roomsResponse(.failure(error)):
                state.isLoading = false
                state.error = error.localizedDescription
                state.rooms = []
                state.selectedPlaceId = nil
                state.detail = nil
                return .cancel(id: CancelID.detail)

            case let .selectRoom(placeId):
                state.selectedPlaceId = placeId
                state.detail = nil
                return loadDetail(&state)

            case .binding(\.range):
                return loadDetail(&state)

            case let .detailResponse(.success(detail)):
                state.detail = detail
                state.detailError = nil
                return .none

            case let .detailResponse(.failure(error)):
                state.detail = nil
                state.detailError = error.localizedDescription
                return .none

            case .binding:
                return .none
            }
        }
    }

    private func loadDetail(_ state: inout State) -> Effect<Action> {
        guard let placeId = state.selectedPlaceId else {
            state.detailError = nil
            return .cancel(id: CancelID.detail)
        }
        let range = state.range
        state.detailError = nil
        return .run { send in
            await send(.detailResponse(Result { try await serverClient.getHeatingRoom(placeId, range) }))
        }
        .cancellable(id: CancelID.detail, cancelInFlight: true)
    }

    /// The rooms of the heating automations; the place comes from the radiators' entities.
    static func rooms(in automations: [AutomationInfo]) -> [Room] {
        var seen = Set<String>()
        return automations
            .filter { $0.type == automationType }
            .compactMap { $0.entities.first?.placeId }
            .filter { seen.insert($0).inserted }
            .map { Room(placeId: $0, name: $0) }
    }
}
