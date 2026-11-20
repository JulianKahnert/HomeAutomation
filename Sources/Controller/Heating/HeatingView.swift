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
import SwiftUI

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
            case let (left?, right?): return left == right ? lhs.offset < rhs.offset : left < right
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return lhs.offset < rhs.offset
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

// MARK: - View

enum HeatingLayout: Equatable {
    case compact, regular
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

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                HeatingScreen(store: store, layout: layout)
                    .navigationTitle("Heizung")
                    .heatingSubtitle(HeatingFormat.fireplaceHint(store.fireplace, now: context.date) ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    FireplaceToolbarButton(isOn: store.fireplace.isOn) { store.send(.setFireplace(!store.fireplace.isOn)) }
                }
            }
            .alert("Kamin nicht geschaltet", isPresented: Binding(get: { store.fireplaceError != nil },
                                                                   set: { if !$0 { store.send(.dismissFireplaceError) } })) {
                Button("OK") {}
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
        if store.error != nil, store.rooms.isEmpty {
            ContentUnavailableView {
                Label("Server nicht erreichbar", systemImage: "wifi.slash")
            } description: {
                Text("Die Heizung kann nicht geladen werden.")
            } actions: {
                Button("Erneut versuchen") { store.send(.refresh) }
            }
        } else if store.rooms.isEmpty, !store.isLoading {
            ContentUnavailableView("Keine Räume", systemImage: "heater.vertical",
                                   description: Text(HeatingFeature.noRoomsHint))
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
                            Text("Wähle links einen Raum.")
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
        HeatingOverviewView(rooms: store.rooms, headline: store.headlineParts, updatedAt: store.updatedAt, selectedPlaceId: store.selectedPlaceId,
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
                                  plotWidthEstimate: layout == .compact ? 290 : 560,
                                  onClose: layout == .compact ? { store.send(.selectRoom(nil)) } : nil)
        } else if store.detailError != nil {
            ContentUnavailableView("Raum nicht ladbar", systemImage: "exclamationmark.triangle",
                                   description: Text("Der Server hat keine Daten für diesen Raum geliefert."))
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
            .environment(\.locale, HeatingFormat.locale)
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
    static var noRooms: HeatingFeature.State { HeatingFeature.State() }
}

#Preview("iPhone hell Übersicht") { HeatingPreview(state: HeatingPreviewState.overview, layout: .compact, scheme: .light) }
#Preview("iPhone dunkel Übersicht") { HeatingPreview(state: HeatingPreviewState.overview, layout: .compact, scheme: .dark) }
#Preview("Mac hell Übersicht") { HeatingPreview(state: HeatingPreviewState.overview, layout: .regular, scheme: .light) }
#Preview("Mac dunkel Übersicht") { HeatingPreview(state: HeatingPreviewState.overview, layout: .regular, scheme: .dark) }
#Preview("iPhone hell 24 h") { HeatingPreview(state: HeatingPreviewState.day, layout: .compact, scheme: .light) }
#Preview("iPhone dunkel 24 h") { HeatingPreview(state: HeatingPreviewState.day, layout: .compact, scheme: .dark) }
#Preview("iPhone hell 7 T") { HeatingPreview(state: HeatingPreviewState.week, layout: .compact, scheme: .light) }
#Preview("iPhone dunkel 7 T") { HeatingPreview(state: HeatingPreviewState.week, layout: .compact, scheme: .dark) }
#Preview("iPhone hell ohne Daten") { HeatingPreview(state: HeatingPreviewState.noData, layout: .compact, scheme: .light) }
#Preview("iPhone dunkel ohne Daten") { HeatingPreview(state: HeatingPreviewState.noData, layout: .compact, scheme: .dark) }
#Preview("iPhone hell Server nicht erreichbar") { HeatingPreview(state: HeatingPreviewState.offline, layout: .compact, scheme: .light) }
#Preview("iPhone dunkel Server nicht erreichbar") { HeatingPreview(state: HeatingPreviewState.offline, layout: .compact, scheme: .dark) }
#Preview("iPhone hell keine Räume") { HeatingPreview(state: HeatingPreviewState.noRooms, layout: .compact, scheme: .light) }
#Preview("Mac hell 24 h") { HeatingPreview(state: HeatingPreviewState.day, layout: .regular, scheme: .light) }
#Preview("Mac dunkel 24 h") { HeatingPreview(state: HeatingPreviewState.day, layout: .regular, scheme: .dark) }
#Preview("Mac hell 7 T") { HeatingPreview(state: HeatingPreviewState.week, layout: .regular, scheme: .light) }
#Preview("Mac dunkel 7 T") { HeatingPreview(state: HeatingPreviewState.week, layout: .regular, scheme: .dark) }
#Preview("Mac hell ohne Daten") { HeatingPreview(state: HeatingPreviewState.noData, layout: .regular, scheme: .light) }
#Preview("Mac dunkel ohne Daten") { HeatingPreview(state: HeatingPreviewState.noData, layout: .regular, scheme: .dark) }
#Preview("Mac hell Server nicht erreichbar") { HeatingPreview(state: HeatingPreviewState.offline, layout: .regular, scheme: .light) }
#Preview("Mac dunkel Server nicht erreichbar") { HeatingPreview(state: HeatingPreviewState.offline, layout: .regular, scheme: .dark) }
