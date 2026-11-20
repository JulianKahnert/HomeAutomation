//
//  HeatingOverviewView.swift
//  ControllerFeatures
//
//  The overview in Variante G "Leicht": a headline and one rounded Δ bar per room, no axes or legend
//

import Charts
import HAModels
import SwiftUI

/// Headline and bars of all rooms. Selecting a room is reported through `onSelect`.
struct HeatingOverviewView: View {
    let rooms: [HeatingOverviewRoom]
    let headline: HeatingHeadline?
    /// The time at the top right of the headline.
    let updatedAt: Date?
    let selectedPlaceId: String?
    /// The fireplace burns: the rooms that follow it show the flame and a soft orange area.
    let fireplaceOn: Bool
    /// The room the info bubble shows; driven by hover or drag, preset in previews.
    @State var hoveredPlaceId: String?
    let onSelect: (String?) -> Void

    @Environment(\.colorScheme) private var scheme

    init(rooms: [HeatingOverviewRoom], headline: HeatingHeadline?, updatedAt: Date? = nil, selectedPlaceId: String?, fireplaceOn: Bool = false,
         hoveredPlaceId: String? = nil,
         onSelect: @escaping (String?) -> Void) {
        self.fireplaceOn = fireplaceOn
        self.rooms = rooms
        self.headline = headline
        self.updatedAt = updatedAt
        self.selectedPlaceId = selectedPlaceId
        self._hoveredPlaceId = State(initialValue: hoveredPlaceId)
        self.onSelect = onSelect
    }

    private let limit = HeatingPalette.barScale
    private var hovered: HeatingOverviewRoom? { rooms.first { $0.placeId == hoveredPlaceId } }

    var body: some View {
        HeatingCard {
            VStack(alignment: .leading, spacing: 8) {
                if let headline {
                    headlineView(headline)
                        // The info bubble takes the headline's place while it is shown.
                        .opacity(hovered == nil ? 1 : 0)
                }
                chart.frame(height: 200)
            }
        }
    }

    private func headlineView(_ headline: HeatingHeadline) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(headline.title).font(.title3.weight(.semibold))
                Text(headline.subtitle).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            if let updatedAt {
                Text(HeatingFormat.time(updatedAt, includingDay: false))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
    }

    private var chart: some View {
        Chart {
            // The fireplace burns: a soft warm column behind the bars of the rooms that follow it.
            if fireplaceOn {
                ForEach(rooms.filter(\.followsFireplace)) { room in
                    RectangleMark(x: .value("Raum", room.placeId), yStart: .value("Δ", -(limit + 0.5)), yEnd: .value("Δ", limit + 0.5), width: .ratio(0.9))
                        .foregroundStyle(Color.orange.opacity(0.14))
                        .clipShape(.rect(cornerRadius: 8))
                }
            }
            RectangleMark(yStart: .value("Δ", -HeatingComfort.band), yEnd: .value("Δ", HeatingComfort.band))
                .foregroundStyle(Color.gray.opacity(0.1))
            RuleMark(y: .value("Δ", 0))
                .foregroundStyle(Color.secondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1))
            ForEach(rooms) { room in
                if let delta = room.delta {
                    let extent = HeatingChartData.barExtent(forDelta: delta)
                    BarMark(x: .value("Raum", room.placeId), yStart: .value("Δ", extent.lowerBound), yEnd: .value("Δ", extent.upperBound), width: .ratio(0.55))
                        .foregroundStyle(HeatingPalette.color(forDelta: delta, scheme: scheme))
                        .clipShape(.rect(cornerRadius: 6))
                } else {
                    // Keeps the category on the axis; the hatched box is drawn in the overlay.
                    BarMark(x: .value("Raum", room.placeId), yStart: .value("Δ", -0.6), yEnd: .value("Δ", 0.6), width: .ratio(0.55))
                        .foregroundStyle(Color.clear)
                }
            }
        }
        // The fireplace columns come first in the chart; without a fixed domain they would move their rooms to the left.
        .chartXScale(domain: rooms.map(\.placeId))
        .chartYScale(domain: -(limit + 0.5)...(limit + 0.5))
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let placeId = value.as(String.self), let axisRoom = rooms.first(where: { $0.placeId == placeId }) {
                        let isSelected = placeId == selectedPlaceId
                        VStack(spacing: 2) {
                            // Selection as a soft tinted pill; the bars keep their full colour.
                            Text(axisRoom.shortName)
                                .font(.caption)
                                .fontWeight(isSelected ? .semibold : .regular)
                                .foregroundStyle(isSelected ? .primary : .secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(isSelected ? HeatingPalette.softFill : .clear, in: .capsule)
                            if rooms.contains(where: \.followsFireplace) {
                                // Always reserves the line, so the plot does not jump with the switch.
                                Image(systemName: "flame.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                    .opacity(fireplaceOn && axisRoom.followsFireplace ? 1 : 0)
                            }
                        }
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    decorations(proxy: proxy, geo: geo)
                    bubble(proxy: proxy, geo: geo)
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                hoveredPlaceId = room(at: drag.location.x, proxy: proxy, geo: geo)?.placeId
                            }
                            .onEnded { drag in
                                hoveredPlaceId = nil
                                // A drag only scrubs the bubble; a tap also opens the room.
                                guard abs(drag.translation.width) < 8,
                                      let room = room(at: drag.location.x, proxy: proxy, geo: geo) else { return }
                                onSelect(selectedPlaceId == room.placeId ? nil : room.placeId)
                            })
                        .onContinuousHover { phase in
                            if case .active(let point) = phase {
                                hoveredPlaceId = room(at: point.x, proxy: proxy, geo: geo)?.placeId
                            } else {
                                hoveredPlaceId = nil
                            }
                        }
                }
            }
        }
        // Room for the bubble, which floats over the headline.
        .padding(.top, 22)
    }

    private func room(at x: CGFloat, proxy: ChartProxy, geo: GeometryProxy) -> HeatingOverviewRoom? {
        guard let plot = proxy.plotFrame, let placeId: String = proxy.value(atX: x - geo[plot].minX) else { return nil }
        return rooms.first { $0.placeId == placeId }
    }

    @ViewBuilder
    private func bubble(proxy: ChartProxy, geo: GeometryProxy) -> some View {
        if let room = hovered, let plot = proxy.plotFrame, let x = proxy.position(forX: room.placeId) {
            let frame = geo[plot]
            // A bottom-aligned box puts the bubble's bottom edge on the plot top.
            HeatingInfoBubble(room: room)
                .frame(width: 320, height: 200, alignment: .bottom)
                .position(x: min(max(frame.minX + x, frame.minX + 120), frame.maxX - 120), y: frame.minY - 100)
                .allowsHitTesting(false)
        }
    }

    /// The hatched "?" bar and the fade at the end of a bar that runs off the plot beyond ±3 K.
    @ViewBuilder
    private func decorations(proxy: ChartProxy, geo: GeometryProxy) -> some View {
        if let plot = proxy.plotFrame {
            let frame = geo[plot]
            let width = frame.width / CGFloat(max(rooms.count, 1)) * 0.55
            let card = HeatingPalette.card(scheme)
            ForEach(rooms) { room in
                if let x = proxy.position(forX: room.placeId) {
                    if let delta = room.delta {
                        if abs(delta) > limit, let tip = proxy.position(forY: delta < 0 ? -limit : limit) {
                            LinearGradient(colors: [card.opacity(0), card.opacity(0.75)],
                                           startPoint: delta < 0 ? .top : .bottom,
                                           endPoint: delta < 0 ? .bottom : .top)
                                .frame(width: width + 2, height: 18)
                                .position(x: frame.minX + x, y: frame.minY + tip + (delta < 0 ? -9 : 9))
                        }
                    } else if let top = proxy.position(forY: 0.6), let bottom = proxy.position(forY: -0.6) {
                        HeatingHatch(isSelected: room.placeId == selectedPlaceId)
                            .clipShape(.rect(cornerRadius: 6))
                            .frame(width: width, height: bottom - top)
                            .position(x: frame.minX + x, y: frame.minY + (top + bottom) / 2)
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}

/// Health-style info bubble: no border, numbers only for the hovered or dragged room.
struct HeatingInfoBubble: View {
    @Environment(\.colorScheme) private var scheme
    let room: HeatingOverviewRoom

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(room.name).font(.caption).foregroundStyle(.secondary)
            if let delta = room.delta {
                Text(HeatingFormat.kelvin(delta))
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(HeatingPalette.color(forDelta: delta, scheme: scheme))
            } else {
                Text("kein Ist-Wert").font(.title3.weight(.semibold))
            }
            Text("Ist \(room.ist.map(HeatingFormat.degrees) ?? "–") · Plan \(room.sollPlan.map(HeatingFormat.degrees) ?? "–")")
                .font(.caption.monospacedDigit())
            Label(sourceText, systemImage: sourceSymbol)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: .rect(cornerRadius: 10))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        .fixedSize()
    }

    private var sourceText: String {
        switch room.istSource {
        case .roomSensor(let name): return "Raumsensor \(name)"
        case .thermostats(let names): return names.count == 1 ? "Thermostat" : "Mittel von \(names.count) Thermostaten"
        }
    }

    private var sourceSymbol: String {
        switch room.istSource {
        case .roomSensor: return "thermometer.medium"
        case .thermostats: return "heater.vertical"
        }
    }
}

// MARK: - Previews

#Preview("Übersicht") {
    let rooms = HeatingFeature.sorted(HeatingPreviewData.overviewRooms)
    HeatingOverviewView(rooms: rooms, headline: HeatingFeature.headlineParts(for: rooms), updatedAt: HeatingPreviewData.now, selectedPlaceId: nil) { _ in }
        .padding(16)
        .frame(width: 402)
}

#Preview("Info-Blase") {
    if let room = HeatingPreviewData.overviewRooms.first {
        HeatingInfoBubble(room: room).padding(16)
    }
}
