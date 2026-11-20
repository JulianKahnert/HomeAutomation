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

    /// Shown when the server knows no heating room.
    static let noRoomsHint = "Es ist keine Heizungsautomatik eingerichtet. Lege in der Konfiguration eine RoomHeating-Automation an."

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
        /// The pin (or "+n" group) whose reason is shown; `nil` for none.
        var selectedPinId: String?
        var isLoading = false
        /// When the overview was loaded; the headline shows the time.
        var updatedAt: Date?
        /// Set when the rooms could not be loaded: the server is not reachable.
        var error: String?
        /// Set when the detail of the selected room could not be loaded.
        var detailError: String?
        /// The fireplace switch (glossary: fireplace mode); off until the server says otherwise.
        var fireplace: FireplaceState = .off
        /// Set when switching the fireplace failed.
        var fireplaceError: String?

        var selectedRoom: HeatingOverviewRoom? { rooms.first { $0.placeId == selectedPlaceId } }

        /// One line about the room that deviates most; `nil` while no room has a Δ.
        var headline: String? { HeatingFeature.headline(for: rooms) }
        /// The headline as bold title and grey subtitle.
        var headlineParts: HeatingHeadline? { HeatingFeature.headlineParts(for: rooms) }
    }

    enum Action: BindableAction, Sendable {
        case binding(BindingAction<State>)
        case detailResponse(Result<HeatingRoomDetail, Error>)
        case dismissFireplaceError
        case fireplaceLoaded(Result<FireplaceState, Error>)
        case fireplaceSwitched(Result<FireplaceState, Error>)
        case overviewResponse(Result<HeatingOverview, Error>)
        case refresh
        case selectPin(String?)
        case selectRoom(String?)
        /// The toolbar button, the push action "Kamin an?" and later the reminder push: switches the fireplace.
        case setFireplace(Bool)
        case task
    }

    @Dependency(\.date) var date
    @Dependency(\.serverClient) var serverClient
    @Dependency(\.date.now) var now

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .task, .refresh:
                state.isLoading = true
                return .merge(
                    .run { send in
                        await send(.overviewResponse(Result { try await serverClient.getHeatingOverview() }))
                    },
                    .run { send in
                        await send(.fireplaceLoaded(Result { try await serverClient.getFireplace() }))
                    }
                )

            case let .fireplaceLoaded(.success(fireplace)):
                state.fireplace = fireplace
                return .none

            case .fireplaceLoaded(.failure):
                // The tab keeps what it knows; the overview shows the error when the server is away.
                return .none

            case let .setFireplace(isOn):
                // Always asks the server, even for the state the tab shows: the tab may be stale (the push action
                // runs in a freshly started app) and the server ignores a repeated request. Shows the new state at
                // once; the server's answer replaces it.
                state.fireplace = isOn ? FireplaceState(isOn: true, since: now) : .off
                state.fireplaceError = nil
                return .run { send in
                    await send(.fireplaceSwitched(Result { try await serverClient.setFireplace(isOn) }))
                }

            case let .fireplaceSwitched(.success(fireplace)):
                state.fireplace = fireplace
                return .none

            case let .fireplaceSwitched(.failure(error)):
                state.fireplaceError = error.localizedDescription
                // Back to what the switch really says.
                return .run { send in
                    await send(.fireplaceLoaded(Result { try await serverClient.getFireplace() }))
                }

            case .dismissFireplaceError:
                state.fireplaceError = nil
                return .none

            case let .overviewResponse(.success(overview)):
                state.isLoading = false
                state.error = nil
                state.updatedAt = date.now
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
                state.selectedPinId = nil
                return loadDetail(&state)

            case let .selectPin(pinId):
                state.selectedPinId = state.selectedPinId == pinId ? nil : pinId
                return .none

            case .binding(\.range):
                state.selectedPinId = nil
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
        guard let parts = headlineParts(for: rooms) else { return nil }
        return parts.isAllInPlan ? parts.title : "\(parts.title) · \(parts.subtitle)"
    }

    static func headlineParts(for rooms: [HeatingOverviewRoom]) -> HeatingHeadline? {
        let deviating = rooms.compactMap { room in room.delta.map { (room, $0) } }
        guard let worst = deviating.max(by: { abs($0.1) < abs($1.1) }) else { return nil }
        switch HeatingComfort(delta: worst.1) {
        case .ok: return HeatingHeadline(title: "Alle Räume im Plan", subtitle: "jeder Raum innerhalb ±0,5 K")
        case .tooCold: return HeatingHeadline(title: "\(worst.0.name) am kältesten", subtitle: "\(HeatingFormat.kelvinAmount(worst.1)) unter Plan")
        case .tooWarm: return HeatingHeadline(title: "\(worst.0.name) am wärmsten", subtitle: "\(HeatingFormat.kelvinAmount(worst.1)) über Plan")
        }
    }
}

/// The overview's headline: a bold title and a grey subtitle.
struct HeatingHeadline: Equatable, Sendable {
    let title: String
    let subtitle: String
    var isAllInPlan: Bool { title == "Alle Räume im Plan" }
}
