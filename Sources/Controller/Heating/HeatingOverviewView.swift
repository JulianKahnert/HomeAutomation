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
    let headline: String?
    let selectedPlaceId: String?
    /// The room the info bubble shows; driven by hover or drag, preset in previews.
    @State var hoveredPlaceId: String?
    let onSelect: (String?) -> Void

    @Environment(\.colorScheme) private var scheme

    init(rooms: [HeatingOverviewRoom], headline: String?, selectedPlaceId: String?, hoveredPlaceId: String? = nil,
         onSelect: @escaping (String?) -> Void) {
        self.rooms = rooms
        self.headline = headline
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
                    Text(headline)
                        .font(.title3.weight(.semibold))
                        // The info bubble takes the headline's place while it is shown.
                        .opacity(hovered == nil ? 1 : 0)
                }
                chart.frame(height: 200)
            }
        }
    }

    private var chart: some View {
        Chart {
            RectangleMark(yStart: .value("Δ", -HeatingPalette.comfortBand), yEnd: .value("Δ", HeatingPalette.comfortBand))
                .foregroundStyle(Color.gray.opacity(0.1))
            RuleMark(y: .value("Δ", 0))
                .foregroundStyle(Color.secondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1))
            ForEach(rooms) { room in
                if let delta = room.delta {
                    BarMark(x: .value("Raum", room.shortName), y: .value("Δ", min(max(delta, -limit), limit)), width: .ratio(0.55))
                        .foregroundStyle(HeatingPalette.color(forDelta: delta, scheme: scheme))
                        .clipShape(.rect(cornerRadius: 6))
                } else {
                    // Keeps the category on the axis; the hatched box is drawn in the overlay.
                    BarMark(x: .value("Raum", room.shortName), yStart: .value("Δ", -0.6), yEnd: .value("Δ", 0.6), width: .ratio(0.55))
                        .foregroundStyle(Color.clear)
                }
            }
        }
        .chartYScale(domain: -(limit + 0.5)...(limit + 0.5))
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let short = value.as(String.self) {
                        let isSelected = rooms.first { $0.shortName == short }?.placeId == selectedPlaceId
                        // Selection as a soft tinted pill; the bars keep their full colour.
                        Text(short)
                            .font(.caption)
                            .fontWeight(isSelected ? .semibold : .regular)
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(isSelected ? Color.accentColor.opacity(0.18) : .clear, in: .capsule)
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
        guard let plot = proxy.plotFrame, let short: String = proxy.value(atX: x - geo[plot].minX) else { return nil }
        return rooms.first { $0.shortName == short }
    }

    @ViewBuilder
    private func bubble(proxy: ChartProxy, geo: GeometryProxy) -> some View {
        if let room = hovered, let plot = proxy.plotFrame, let x = proxy.position(forX: room.shortName) {
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
                if let x = proxy.position(forX: room.shortName) {
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
        case .roomSensor(let name): "Raumsensor \(name)"
        case .thermostats(let names): names.count == 1 ? "Thermostat" : "Mittel von \(names.count) Thermostaten"
        }
    }

    private var sourceSymbol: String {
        switch room.istSource {
        case .roomSensor: "thermometer.medium"
        case .thermostats: "heater.vertical"
        }
    }
}
