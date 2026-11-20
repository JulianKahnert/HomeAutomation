//
//  HeatingFeature.swift
//  ControllerFeatures
//
//  The Heizung tab: the overview of all rooms and the detail of the selected room
//

import ComposableArchitecture
import Foundation
import HAModels

@Reducer
struct HeatingFeature: Sendable {

    private enum CancelID {
        case detail
    }

    @ObservableState
    struct State: Equatable, Sendable {
        /// Coldest first; rooms without an actual value last.
        var rooms: [HeatingOverviewRoom] = []
        /// The week heatmap of the overview endpoint.
        var heatmap: [HeatingHeatmapCell] = []
        var selectedPlaceId: String?
        var range: HeatingRange = .day
        var detail: HeatingRoomDetail?
        var isLoading = false
        /// Set when the rooms could not be loaded: the server is not reachable.
        var error: String?
        /// Set when the detail of the selected room could not be loaded.
        var detailError: String?

        var selectedRoom: HeatingOverviewRoom? { rooms.first { $0.placeId == selectedPlaceId } }

        /// One line about the room that deviates most; `nil` while no room has a Δ.
        var headline: String? { HeatingFeature.headline(for: rooms) }
    }

    enum Action: BindableAction, Sendable {
        case binding(BindingAction<State>)
        case detailResponse(Result<HeatingRoomDetail, Error>)
        case overviewResponse(Result<HeatingOverview, Error>)
        case refresh
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
                    await send(.overviewResponse(Result { try await serverClient.getHeatingOverview() }))
                }

            case let .overviewResponse(.success(overview)):
                state.isLoading = false
                state.error = nil
                state.rooms = Self.sorted(overview.rooms)
                state.heatmap = overview.heatmap
                if state.selectedRoom == nil {
                    state.selectedPlaceId = nil
                    state.detail = nil
                }
                return loadDetail(&state)

            case let .overviewResponse(.failure(error)):
                state.isLoading = false
                state.error = error.localizedDescription
                state.rooms = []
                state.heatmap = []
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

    /// Coldest first (smallest Δ), rooms without a Δ last; equal Δ keep the server's order.
    static func sorted(_ rooms: [HeatingOverviewRoom]) -> [HeatingOverviewRoom] {
        let indexed = rooms.enumerated().sorted { lhs, rhs in
            switch (lhs.element.delta, rhs.element.delta) {
            case let (left?, right?): left == right ? lhs.offset < rhs.offset : left < right
            case (.some, .none): true
            case (.none, .some): false
            case (.none, .none): lhs.offset < rhs.offset
            }
        }
        return indexed.map(\.element)
    }

    /// "Bad OG am kältesten · 3,7 K unter Plan", "… am wärmsten · 2,0 K über Plan" or "Alle Räume im Plan".
    static func headline(for rooms: [HeatingOverviewRoom]) -> String? {
        let deviating = rooms.compactMap { room in room.delta.map { (room, $0) } }
        guard let worst = deviating.max(by: { abs($0.1) < abs($1.1) }) else { return nil }
        switch HeatingComfort(delta: worst.1) {
        case .ok: return "Alle Räume im Plan"
        case .tooCold: return "\(worst.0.name) am kältesten · \(HeatingFormat.kelvinAmount(worst.1)) unter Plan"
        case .tooWarm: return "\(worst.0.name) am wärmsten · \(HeatingFormat.kelvinAmount(worst.1)) über Plan"
        }
    }
}
