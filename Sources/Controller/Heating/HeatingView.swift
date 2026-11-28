//
//  HeatingView.swift
//  ControllerFeatures
//
//  The Heizung tab: the feature (overview of all rooms, detail of the selected room) and its view: one column
//  on iPhone, two columns on Mac and iPad (bars left, detail or placeholder right)
//

import ComposableArchitecture
import Foundation
import HAModels
import ServerClient
import SwiftUI

@Reducer
struct HeatingFeature: Sendable {

    /// Shown when the server knows no heating room.
    static var noRoomsHint: String {
        String(localized: "No heating automation is set up. Create a RoomHeating automation in the configuration.", bundle: .module)
    }

    private enum CancelID {
        case detail
        case fireplaceReload
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
        /// When the overview was last loaded, `nil` before the first answer.
        var updatedAt: Date?
        /// Set when the last reload failed: the server is not reachable. What was loaded before stays shown.
        var error: String?
        /// Set when the detail of the selected room could not be loaded.
        var detailError: String?
        /// The fireplace switch (glossary: fireplace mode); off until the server says otherwise.
        var fireplace: FireplaceState = .off
        /// Set when switching the fireplace failed.
        var fireplaceError: String?

        var selectedRoom: HeatingOverviewRoom? { rooms.first { $0.placeId == selectedPlaceId } }
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

    @Dependency(\.continuousClock) var clock
    @Dependency(\.date) var date
    @Dependency(\.serverClient) var serverClient

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .task, .refresh:
                // The tab keeps showing what it has until the answer arrives, so a reload does not flicker.
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
                state.fireplace = isOn ? FireplaceState(isOn: true, since: date.now) : .off
                state.fireplaceError = nil
                return .run { send in
                    await send(.fireplaceSwitched(Result { try await serverClient.setFireplace(isOn) }))
                }

            case let .fireplaceSwitched(.success(fireplace)):
                state.fireplace = fireplace
                return .none

            case let .fireplaceSwitched(.failure(error)) where error as? ServerClientError == .busy:
                // The server queued the switch and will still apply it: keep the shown state and look again soon.
                return .run { send in
                    try await clock.sleep(for: .seconds(5))
                    await send(.fireplaceLoaded(Result { try await serverClient.getFireplace() }))
                }
                .cancellable(id: CancelID.fireplaceReload, cancelInFlight: true)

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
                state.error = error.localizedDescription
                return .none

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
            case let (left?, right?): return left == right ? lhs.offset < rhs.offset : left < right
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return lhs.offset < rhs.offset
            }
        }
        return indexed.map(\.element)
    }
}

// MARK: - View

enum HeatingLayout: Equatable {
    case compact, regular

    /// The plot width of the room detail's chart until it measured itself; the pins stack with it.
    var plotWidthEstimate: CGFloat { self == .compact ? 290 : 560 }
}

/// The tab with its navigation title and loading.
struct HeatingView: View {
    @Bindable var store: StoreOf<HeatingFeature>
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: HeatingLayout { sizeClass == .compact ? .compact : .regular }
    #else
    private var layout: HeatingLayout { .regular }
    #endif

    /// The clock of the subtitle "endet in 2 h"; ticks only while the fireplace burns, so the charts are not
    /// rebuilt every minute.
    @State private var now = Date()

    var body: some View {
        NavigationStack {
            HeatingScreen(store: store, layout: layout)
                .background(HeatingPalette.screen)
                .navigationTitle(String(localized: "Heating", bundle: .module))
                .heatingSubtitle(HeatingFormat.fireplaceHint(store.fireplace, now: now) ?? "")
            .task(id: store.fireplace.isOn) {
                now = Date()
                guard store.fireplace.isOn else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    now = Date()
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    FireplaceToolbarButton(isOn: store.fireplace.isOn) { store.send(.setFireplace(!store.fireplace.isOn)) }
                }
            }
            .alert(String(localized: "Fireplace not switched", bundle: .module), isPresented: Binding(get: { store.fireplaceError != nil },
                                                                   set: { if !$0 { store.send(.dismissFireplaceError) } })) {
                Button(String(localized: "OK", bundle: .module)) {}
            } message: {
                Text(store.fireplaceError ?? "")
            }
        }
        .task { await store.send(.task).finish() }
    }
}

/// The content of the tab, drivable from plain state for previews.
struct HeatingScreen: View {
    @Bindable var store: StoreOf<HeatingFeature>
    let layout: HeatingLayout

    var body: some View {
        // Decided by what was loaded, never by a reload in flight: the content stays until the answer arrives.
        if store.rooms.isEmpty, store.updatedAt != nil {
            ContentUnavailableView {
                Label(String(localized: "No Rooms", bundle: .module), systemImage: "heater.vertical")
            } description: {
                Text(HeatingFeature.noRoomsHint)
            }
        } else if store.rooms.isEmpty, store.error != nil {
            ContentUnavailableView {
                Label(String(localized: "Server unreachable", bundle: .module), systemImage: "wifi.slash")
            } description: {
                Text("The heating cannot be loaded.", bundle: .module)
            } actions: {
                Button(String(localized: "Try Again", bundle: .module)) { store.send(.refresh) }
            }
        } else if store.rooms.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if layout == .compact {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    overview
                    if store.selectedPlaceId != nil {
                        detail
                    }
                    heatmap
                }
                .padding(16)
            }
            .refreshable { await store.send(.refresh).finish() }
        } else {
            HStack(alignment: .top, spacing: 16) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        overview
                        heatmap
                    }
                    .padding(16)
                }
                .frame(width: 420)
                ScrollView {
                    Group {
                        if store.selectedPlaceId == nil {
                            Text("Select a room on the left.", bundle: .module)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 200)
                        } else {
                            detail
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private var overview: some View {
        HeatingOverviewView(rooms: store.rooms, selectedPlaceId: store.selectedPlaceId,
                            fireplaceOn: store.fireplace.isOn) {
            store.send(.selectRoom($0))
        }
    }

    private var heatmap: some View {
        HeatingHeatmapView(rooms: store.rooms, cells: store.heatmap, selectedPlaceId: store.selectedPlaceId)
    }

    @ViewBuilder
    private var detail: some View {
        if let detail = store.detail {
            HeatingRoomDetailView(detail: detail, range: $store.range, selectedPinId: store.selectedPinId,
                                  onSelectPin: { store.send(.selectPin($0)) }, layout: layout,
                                  onClose: layout == .compact ? { store.send(.selectRoom(nil)) } : nil)
        } else if store.detailError != nil {
            ContentUnavailableView {
                Label(String(localized: "Room cannot be loaded", bundle: .module), systemImage: "exclamationmark.triangle")
            } description: {
                Text("The server returned no data for this room.", bundle: .module)
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 200)
        }
    }
}

// MARK: - Previews

private struct HeatingPreview: View {
    let state: HeatingFeature.State
    let layout: HeatingLayout
    let scheme: ColorScheme

    var body: some View {
        HeatingScreen(store: Store(initialState: state) { HeatingFeature() }, layout: layout)
            .frame(width: layout == .compact ? 402 : 1_120, height: layout == .compact ? 900 : 760)
            .background(Color(white: scheme == .dark ? 0.08 : 0.96))
            .environment(\.colorScheme, scheme)
    }
}

private enum HeatingPreviewState {
    static var overview: HeatingFeature.State { HeatingPreviewData.state() }
    static var day: HeatingFeature.State { HeatingPreviewData.state("Bad OG") }
    static var week: HeatingFeature.State { HeatingPreviewData.state("Schlafzimmer", range: .week) }
    static var noData: HeatingFeature.State { HeatingPreviewData.state("Kaminzimmer") }
    static var offline: HeatingFeature.State {
        var state = HeatingFeature.State()
        state.error = "offline"
        return state
    }
    static var noRooms: HeatingFeature.State {
        var state = HeatingFeature.State()
        state.updatedAt = HeatingPreviewData.now
        return state
    }
}

#Preview("iPhone light overview") { HeatingPreview(state: HeatingPreviewState.overview, layout: .compact, scheme: .light) }
#Preview("iPhone dark overview") { HeatingPreview(state: HeatingPreviewState.overview, layout: .compact, scheme: .dark) }
#Preview("Mac light overview") { HeatingPreview(state: HeatingPreviewState.overview, layout: .regular, scheme: .light) }
#Preview("Mac dark overview") { HeatingPreview(state: HeatingPreviewState.overview, layout: .regular, scheme: .dark) }
#Preview("iPhone light 24 h") { HeatingPreview(state: HeatingPreviewState.day, layout: .compact, scheme: .light) }
#Preview("iPhone dark 24 h") { HeatingPreview(state: HeatingPreviewState.day, layout: .compact, scheme: .dark) }
#Preview("iPhone light 7 d") { HeatingPreview(state: HeatingPreviewState.week, layout: .compact, scheme: .light) }
#Preview("iPhone dark 7 d") { HeatingPreview(state: HeatingPreviewState.week, layout: .compact, scheme: .dark) }
#Preview("iPhone light no data") { HeatingPreview(state: HeatingPreviewState.noData, layout: .compact, scheme: .light) }
#Preview("iPhone dark no data") { HeatingPreview(state: HeatingPreviewState.noData, layout: .compact, scheme: .dark) }
#Preview("iPhone light server unreachable") { HeatingPreview(state: HeatingPreviewState.offline, layout: .compact, scheme: .light) }
#Preview("iPhone dark server unreachable") { HeatingPreview(state: HeatingPreviewState.offline, layout: .compact, scheme: .dark) }
#Preview("iPhone light no rooms") { HeatingPreview(state: HeatingPreviewState.noRooms, layout: .compact, scheme: .light) }
#Preview("Mac light 24 h") { HeatingPreview(state: HeatingPreviewState.day, layout: .regular, scheme: .light) }
#Preview("Mac dark 24 h") { HeatingPreview(state: HeatingPreviewState.day, layout: .regular, scheme: .dark) }
#Preview("Mac light 7 d") { HeatingPreview(state: HeatingPreviewState.week, layout: .regular, scheme: .light) }
#Preview("Mac dark 7 d") { HeatingPreview(state: HeatingPreviewState.week, layout: .regular, scheme: .dark) }
#Preview("Mac light no data") { HeatingPreview(state: HeatingPreviewState.noData, layout: .regular, scheme: .light) }
#Preview("Mac dark no data") { HeatingPreview(state: HeatingPreviewState.noData, layout: .regular, scheme: .dark) }
#Preview("Mac light server unreachable") { HeatingPreview(state: HeatingPreviewState.offline, layout: .regular, scheme: .light) }
#Preview("Mac dark server unreachable") { HeatingPreview(state: HeatingPreviewState.offline, layout: .regular, scheme: .dark) }
