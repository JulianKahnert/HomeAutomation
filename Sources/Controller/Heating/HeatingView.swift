//
//  HeatingView.swift
//  ControllerFeatures
//
//  The Heizung tab: one column on iPhone, two columns on Mac and iPad (bars left, detail or placeholder right)
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
                                   description: Text("Es ist keine Heizungsautomatik eingerichtet."))
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
            HeatingRoomDetailView(detail: detail, range: $store.range, onClose: layout == .compact ? { store.send(.selectRoom(nil)) } : nil)
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
