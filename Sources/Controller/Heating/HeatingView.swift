//
//  HeatingView.swift
//  ControllerFeatures
//
//  The Heizung tab: one column on iPhone, two columns on Mac and iPad
//

import ComposableArchitecture
import HAModels
import SwiftUI

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
            HeatingScreen(store: store, layout: layout)
                .navigationTitle("Heizung")
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
                                   description: Text("Es ist keine Heizungsautomatik eingerichtet."))
        } else if layout == .compact {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HeatingRoomPicker(rooms: store.rooms, selectedPlaceId: store.selectedPlaceId) { store.send(.selectRoom($0)) }
                    detail
                }
                .padding(16)
            }
            .refreshable { await store.send(.refresh).finish() }
        } else {
            HStack(alignment: .top, spacing: 16) {
                ScrollView {
                    HeatingRoomPicker(rooms: store.rooms, selectedPlaceId: store.selectedPlaceId, vertical: true) { store.send(.selectRoom($0)) }
                        .padding(16)
                }
                .frame(width: 320)
                ScrollView {
                    detail.padding(16)
                }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let detail = store.detail {
            HeatingRoomDetailView(detail: detail, range: $store.range)
        } else if store.detailError != nil {
            ContentUnavailableView("Raum nicht ladbar", systemImage: "exclamationmark.triangle",
                                   description: Text("Der Server hat keine Daten für diesen Raum geliefert."))
        } else if store.selectedPlaceId == nil {
            ContentUnavailableView("Raum wählen", systemImage: "heater.vertical",
                                   description: Text("Wähle einen Raum."))
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 200)
        }
    }
}

/// Rooms as pills in a row (iPhone) or a column (Mac, iPad); T3 replaces it with the overview bars.
struct HeatingRoomPicker: View {
    let rooms: [HeatingFeature.Room]
    let selectedPlaceId: String?
    var vertical = false
    let onSelect: (String?) -> Void

    var body: some View {
        let layout = vertical ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        let content = layout {
            ForEach(rooms) { room in
                Button(room.name) { onSelect(room.placeId) }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(room.placeId == selectedPlaceId ? Color.primary.opacity(0.12) : .clear))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.15)))
            }
        }
        if vertical {
            content
        } else {
            ScrollView(.horizontal, showsIndicators: false) { content }
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
    static var day: HeatingFeature.State { HeatingPreviewData.state("Bad OG") }
    static var week: HeatingFeature.State { HeatingPreviewData.state("Küche", range: .week) }
    static var noData: HeatingFeature.State { HeatingPreviewData.state("Kaminzimmer") }
    static var offline: HeatingFeature.State {
        var state = HeatingFeature.State()
        state.error = "offline"
        return state
    }
    static var noRooms: HeatingFeature.State { HeatingFeature.State() }
}

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
