import Charts
import SwiftUI

/// Variant G, "Leicht": F's content, read at a glance like Apple Health, Weather and Fitness.
/// One plain-language headline, no axes or legends on the overview, numbers only on selection
/// (the selection value replaces the header), quiet pins, soft popovers.
struct LightVariant: View {
    var layout: FLayout = .compact
    var loadState: FLoadState = .loaded
    @State var selectedRoomID: String?
    @State var hoveredRoomID: String?
    @State var range: FRange = .day
    @State var pinID: String?
    @State var crosshair: Date?
    @State var heatmapCellID: String?
    /// Fireplace switch candidates (H-A…H-D); nil keeps G as it was.
    var fireplace: FireplacePlacement?
    @State var fireplaceOn = true

    private func fireplaceRoom(_ id: String) -> FRoom {
        FData.room(id).fireplace(fireplace == nil || fireplaceOn)
    }

    var body: some View {
        switch loadState {
        case .loaded:
            loaded
        case .serverUnreachable:
            emptyState {
                ContentUnavailableView {
                    Label("Server nicht erreichbar", systemImage: "wifi.exclamationmark")
                } description: {
                    Text("Keine Verbindung zum HomeAutomation-Server.")
                } actions: {
                    Button("Erneut versuchen") {}
                        .buttonStyle(.borderedProminent)
                }
            }
        case .noRooms:
            emptyState {
                ContentUnavailableView(
                    "Keine Räume",
                    systemImage: "heater.vertical",
                    description: Text("In der Heizungskonfiguration ist noch kein Raum eingetragen.")
                )
            }
        }
    }

    private var selection: Binding<String?> {
        Binding(
            get: { selectedRoomID },
            set: { selectedRoomID = $0; pinID = nil; crosshair = nil }
        )
    }

    @ViewBuilder
    private var loaded: some View {
        GScreen(
            navTrailing: fireplace == .toolbar ? AnyView(GFireplaceToolbarButton(isOn: $fireplaceOn)) : nil,
            hint: fireplace == .toolbar && fireplaceOn ? "Kamin an · \(FireplaceInfo.endText)" : nil
        ) {
            switch layout {
            case .compact:
                VStack(alignment: .leading, spacing: 16) {
                    overviewCard
                    if let room = selectedRoomID.map(fireplaceRoom) {
                        detailCard(room)
                    }
                    heatmapCard
                }
            case .regular:
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 16) {
                        overviewCard
                        heatmapCard
                    }
                    .frame(width: FLayout.leftColumnWidth)
                    if let room = selectedRoomID.map(fireplaceRoom) {
                        detailCard(room)
                    } else {
                        FCard {
                            ContentUnavailableView("Raum wählen", systemImage: "chart.bar.xaxis", description: Text("Wähle links einen Raum."))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .frame(maxHeight: .infinity)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .environment(\.fireplaceOn, fireplace == nil ? nil : fireplaceOn)
    }

    private var overviewCard: some View {
        FCard {
            GDeltaBars(
                selectedRoomID: selection, hoveredRoomID: $hoveredRoomID,
                headlineTrailing: fireplace == .headlineButton ? AnyView(GFireplaceButton(isOn: $fireplaceOn)) : nil,
                accessory: fireplace == .row ? AnyView(GFireplaceRow(isOn: $fireplaceOn)) : nil
            )
        }
    }

    private var heatmapCard: some View {
        FCard {
            Text("Woche").font(.headline)
            GWeekHeatmap(selectedRoomID: selectedRoomID, cellID: $heatmapCellID)
        }
    }

    private func detailCard(_ room: FRoom) -> some View {
        FCard {
            GRoomDetail(
                room: room, layout: layout, range: $range, pinID: $pinID, crosshair: $crosshair,
                fireplaceOn: fireplace == .detailHeader && room.hasFireplace ? $fireplaceOn : nil,
                onClose: layout == .compact ? { selection.wrappedValue = nil } : nil
            )
        }
    }

    private func emptyState(@ViewBuilder _ content: () -> some View) -> some View {
        GScreen {
            content()
                .frame(maxWidth: .infinity, minHeight: layout == .compact ? 560 : 480)
        }
    }
}

struct GScreen<Content: View>: View {
    var navTrailing: AnyView?
    var hint: String?
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let navTrailing {
                    HStack { Spacer(); navTrailing }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Heizung").font(.largeTitle.bold())
                    if let hint { Text(hint).font(.subheadline).foregroundStyle(.secondary) }
                }
                content
            }
            .padding(16)
        }
        .background(FColor.grouped)
    }
}

enum GStyle {
    static let gapOpacity = (cold: 0.18, ok: 0.12, warm: 0.2)
    static let areaOpacity = 0.08
    static let soft = Color.secondary.opacity(0.12)
    /// Ist line: opaque grey at about 65 % of primary, so it stays crisp over the gap fill
    /// without the hardness of black (light) or white (dark).
    static let istLine = FAdaptive(light: Color(white: 0.38), dark: Color(white: 0.68))
}

// MARK: - Overview

struct GDeltaBars: View {
    @Binding var selectedRoomID: String?
    @Binding var hoveredRoomID: String?
    var headlineTrailing: AnyView?
    var accessory: AnyView?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.fireplaceOn) private var fireplaceOn

    private let rooms = FData.sortedRooms
    /// The clipped end fades into the card instead of carrying an extra marker.
    private var cardColor: Color { colorScheme == .dark ? FColor.card.dark : FColor.card.light }
    private let limit = 3.0

    /// Only hover or drag shows the callout; a selected room keeps just the pill on its name.
    private var highlighted: FRoom? {
        hoveredRoomID.flatMap { id in rooms.first { $0.id == id } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headline
                // Health pattern: the selection callout takes the headline's place.
                .opacity(highlighted == nil ? 1 : 0)
            accessory
            chart
                .frame(height: 200)
        }
    }

    private var headline: some View {
        let coldest = rooms.compactMap { room in room.delta.map { (room, $0) } }.min { $0.1 < $1.1 }
        let warmest = rooms.compactMap { room in room.delta.map { (room, $0) } }.max { $0.1 < $1.1 }
        let (title, detail): (String, String) = if let coldest, coldest.1 < -FColor.comfort {
            ("\(coldest.0.name) am kältesten", "\(V3Fmt.kelvin(abs(coldest.1)).dropFirst()) unter Plan")
        } else if let warmest, warmest.1 > FColor.comfort {
            ("\(warmest.0.name) am wärmsten", "\(V3Fmt.kelvin(warmest.1).dropFirst()) über Plan")
        } else {
            ("Alle Räume im Plan", "jeder Raum innerhalb ±0,5 K")
        }
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            if let headlineTrailing {
                headlineTrailing
            } else {
                Text(Fmt.time(FData.now)).font(.caption).foregroundStyle(.tertiary).monospacedDigit()
            }
        }
    }

    private var chart: some View {
        Chart {
            // Fireplace on: a soft warm column behind the bars of the rooms it switches to Modus Aus.
            if fireplaceOn == true {
                ForEach(rooms.filter(\.hasFireplace)) { room in
                    RectangleMark(x: .value("Raum", room.short), yStart: .value("Δ", -(limit + 0.5)), yEnd: .value("Δ", limit + 0.5), width: .ratio(0.9))
                        .foregroundStyle(Color.orange.opacity(0.14))
                        .clipShape(.rect(cornerRadius: 8))
                }
            }
            RectangleMark(yStart: .value("Δ", -FColor.comfort), yEnd: .value("Δ", FColor.comfort))
                .foregroundStyle(FColor.ok.opacity(0.08))
            RuleMark(y: .value("Δ", 0))
                .foregroundStyle(Color.secondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1))
            ForEach(rooms) { room in
                if let delta = room.delta {
                    BarMark(x: .value("Raum", room.short), y: .value("Δ", min(max(delta, -limit), limit)), width: .ratio(0.55))
                        .foregroundStyle(FColor.delta(delta))
                        .clipShape(.rect(cornerRadius: 6))
                } else {
                    BarMark(x: .value("Raum", room.short), yStart: .value("Δ", -0.6), yEnd: .value("Δ", 0.6), width: .ratio(0.55))
                        .foregroundStyle(Color.clear)
                }
            }
            if let room = highlighted {
                RuleMark(x: .value("Raum", room.short), yStart: .value("Δ", max(min(max(room.delta ?? 0.6, -limit), limit), 0.6)), yEnd: .value("Δ", limit + 0.5))
                    .foregroundStyle(Color.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartYScale(domain: -(limit + 0.5)...(limit + 0.5))
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let short = value.as(String.self) {
                        let isSelected = rooms.first { $0.short == short }?.id == selectedRoomID
                        // Selection as a soft tinted pill; bars keep their full colour.
                        VStack(spacing: 2) {
                            Text(short)
                                .font(.caption)
                                .fontWeight(isSelected ? .semibold : .regular)
                                .foregroundStyle(isSelected ? .primary : .secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(isSelected ? GStyle.soft : .clear, in: .capsule)
                            if let fireplaceOn {
                                // Always reserves the line, so the plot does not jump with the switch.
                                Image(systemName: "flame.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                    .opacity(fireplaceOn && rooms.first { $0.short == short }?.hasFireplace == true ? 1 : 0)
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
                    callout(proxy: proxy, geo: geo)
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                hoveredRoomID = room(at: drag.location.x, proxy: proxy, geo: geo)?.id
                            }
                            .onEnded { drag in
                                hoveredRoomID = nil
                                // A drag only scrubs the callout; a tap also opens the room.
                                guard abs(drag.translation.width) < 8,
                                      let room = room(at: drag.location.x, proxy: proxy, geo: geo) else { return }
                                selectedRoomID = selectedRoomID == room.id ? nil : room.id
                            })
                        .onContinuousHover { phase in
                            if case .active(let point) = phase {
                                hoveredRoomID = room(at: point.x, proxy: proxy, geo: geo)?.id
                            } else {
                                hoveredRoomID = nil
                            }
                        }
                }
            }
        }
        // Room for the callout, which floats over the headline.
        .padding(.top, 22)
    }

    private func room(at x: CGFloat, proxy: ChartProxy, geo: GeometryProxy) -> FRoom? {
        guard let plot = proxy.plotFrame, let short: String = proxy.value(atX: x - geo[plot].minX) else { return nil }
        return rooms.first { $0.short == short }
    }

    /// Drawn in the overlay, not as a chart annotation: there `.regularMaterial` has no backdrop
    /// and renders as a flat dark box.
    @ViewBuilder
    private func callout(proxy: ChartProxy, geo: GeometryProxy) -> some View {
        if let room = highlighted, let plot = proxy.plotFrame, let x = proxy.position(forX: room.short) {
            let frame = geo[plot]
            // A bottom-aligned box puts the callout's bottom edge on the plot top.
            GBarCallout(room: room)
                .frame(width: 320, height: 200, alignment: .bottom)
                .position(x: min(max(frame.minX + x, frame.minX + 120), frame.maxX - 120), y: frame.minY - 100)
                .allowsHitTesting(false)
        }
    }

    /// The hatched "?" box, and a fade at the end of a bar clipped at ±3 K.
    @ViewBuilder
    private func decorations(proxy: ChartProxy, geo: GeometryProxy) -> some View {
        if let plot = proxy.plotFrame {
            let frame = geo[plot]
            let width = frame.width / CGFloat(rooms.count) * 0.55
            ForEach(rooms) { room in
                if let x = proxy.position(forX: room.short) {
                    if let delta = room.delta {
                        if abs(delta) > limit, let tip = proxy.position(forY: delta < 0 ? -limit : limit) {
                            LinearGradient(
                                colors: [cardColor.opacity(0), cardColor.opacity(0.75)],
                                startPoint: delta < 0 ? .top : .bottom,
                                endPoint: delta < 0 ? .bottom : .top
                            )
                            .frame(width: width + 2, height: 18)
                            .position(x: frame.minX + x, y: frame.minY + tip + (delta < 0 ? -9 : 9))
                        }
                    } else if let top = proxy.position(forY: 0.6), let bottom = proxy.position(forY: -0.6) {
                        FHatch()
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

/// Health-style selection callout: no border, values only for the selected room.
struct GBarCallout: View {
    let room: FRoom

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(room.name).font(.caption).foregroundStyle(.secondary)
            if let delta = room.delta {
                Text(V3Fmt.kelvin(delta))
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(FColor.delta(delta))
            } else {
                Text("kein Ist-Wert").font(.title3.weight(.semibold))
            }
            Text("Ist \(V3Fmt.deg(room.current.ist)) · Plan \(V3Fmt.deg(room.current.sollPlan))")
                .font(.caption.monospacedDigit())
            Label(room.istSource.text, systemImage: room.istSource.symbol)
                .labelStyle(FCompactLabel())
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: .rect(cornerRadius: 10))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        .fixedSize()
    }
}

// MARK: - Detail

struct GRoomDetail: View {
    let room: FRoom
    let layout: FLayout
    @Binding var range: FRange
    @Binding var pinID: String?
    @Binding var crosshair: Date?
    /// C: the fireplace switch as the head of the Kaminzimmer detail.
    var fireplaceOn: Binding<Bool>?
    let onClose: (() -> Void)?

    private var domain: ClosedRange<Date> { range.domain }
    private var samples: [FSample] { room.samples.filter { domain.contains($0.date) } }

    private var pins: [FEvent] {
        room.events.compactMap { event in
            guard range != .week || event.kind != .plan else { return nil }
            if domain.contains(event.date) { return event }
            guard let end = event.end, end > domain.lowerBound, event.date < domain.lowerBound else { return nil }
            var clipped = event
            clipped.pinDate = domain.lowerBound
            return clipped
        }
    }

    private var areas: [FEvent] {
        room.events.filter { event in
            guard let end = event.end else { return false }
            return end > domain.lowerBound && event.date < domain.upperBound
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                GDetailHeader(room: room, date: crosshair)
                Spacer()
                if let onClose {
                    Button("Schließen", systemImage: "xmark.circle.fill", action: onClose)
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                        .buttonStyle(.plain)
                }
            }
            if let fireplaceOn {
                GFireplaceRow(isOn: fireplaceOn).padding(.vertical, 4)
            }
            Picker("Zeitraum", selection: $range) {
                ForEach(FRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: range) {
                pinID = nil
                if let date = crosshair, !domain.contains(date) { crosshair = nil }
            }
            .padding(.bottom, 8)

            GSollIstChart(room: room, range: range, samples: samples, pins: pins, areas: areas, plotWidth: layout.plotWidth, pinID: $pinID, crosshair: $crosshair)
            GValveChart(room: room, range: range, samples: samples, areas: areas, crosshair: $crosshair)
                .padding(.top, 8)
        }
    }
}

/// Current Ist big, Plan secondary. While the crosshair is active the values at that time take
/// its place, with Δ, the time and the Ist source.
struct GDetailHeader: View {
    let room: FRoom
    let date: Date?

    var body: some View {
        let sample = date.map(room.sample(at:)) ?? room.current
        VStack(alignment: .leading, spacing: 2) {
            if let date {
                Text("\(room.name) · \(V3Fmt.dayTime(room.sample(at: date).date))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                Text(room.name).font(.headline)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let ist = sample.ist {
                    Text(V3Fmt.deg(ist)).font(.largeTitle.weight(.semibold).monospacedDigit())
                } else {
                    Text("Kein Ist-Wert").font(.title2.weight(.semibold)).foregroundStyle(.secondary)
                }
                Text("Plan \(V3Fmt.deg(sample.sollPlan))")
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let delta = sample.delta {
                    Text(V3Fmt.kelvin(delta))
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(FColor.delta(delta))
                }
            }
            if date != nil {
                Label(room.istSource.text, systemImage: room.istSource.symbol)
                    .labelStyle(FCompactLabel())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if sample.ist == nil, let last = room.lastIst {
                Text("kein Ist-Wert seit \(V3Fmt.dayTime(last.date))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

func gTimeAxis(_ range: FRange) -> some AxisContent {
    let (component, count): (Calendar.Component, Int) = switch range {
    case .twoHours: (.minute, 30)
    case .day: (.hour, 6)
    case .week: (.day, 1)
    }
    return AxisMarks(values: .stride(by: component, count: count)) { value in
        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(GStyle.soft)
        AxisValueLabel(centered: range == .week) {
            if let date = value.as(Date.self) {
                Text(range == .week ? date.formatted(.dateTime.weekday(.short).locale(Fmt.de)) : Fmt.time(date))
                    .monospacedDigit()
            }
        }
    }
}

/// Trailing labels with one width in both charts, so plots and crosshair line up.
func gYLabel(_ text: String) -> some View {
    Text(text).monospacedDigit().lineLimit(1).fixedSize().frame(width: 36, alignment: .leading)
}

struct GSollIstChart: View {
    let room: FRoom
    let range: FRange
    let samples: [FSample]
    let pins: [FEvent]
    let areas: [FEvent]
    let plotWidth: CGFloat
    @Binding var pinID: String?
    @Binding var crosshair: Date?

    private static let pinWidth: CGFloat = 20
    private static let rowHeight: CGFloat = 20
    private static let popoverWidth: CGFloat = 240

    @Environment(\.colorScheme) private var colorScheme

    private var domain: ClosedRange<Date> { range.domain }
    private var hasIst: Bool { samples.contains { $0.ist != nil } }

    /// Thin orange over near-black turns brown, so dark mode needs a lighter tint at more
    /// opacity to read as soft orange, like the bars.
    /// Light: Weather-style fill, strong at the Ist line and fading towards the Plan-Soll.
    /// Dark: any low-opacity or whitened orange over the near-black card reads brown or tan,
    /// so the fill stays fully saturated at a flat, higher opacity, the same hue as the bars.
    private func gapStyle(_ name: String, _ color: Color, _ opacity: Double) -> AnyShapeStyle {
        if colorScheme == .dark {
            return AnyShapeStyle(color.opacity(name == "ok" ? 0.28 : name == "warm" ? 0.6 : 0.5))
        }
        guard name != "ok" else { return AnyShapeStyle(color.opacity(opacity)) }
        // Warm: Ist above Plan, so strong at the top; cold: strong at the bottom.
        return AnyShapeStyle(LinearGradient(
            colors: [color.opacity(opacity * 2), color.opacity(opacity * 0.4)],
            startPoint: name == "warm" ? .top : .bottom,
            endPoint: name == "warm" ? .bottom : .top
        ))
    }

    /// One quiet row: a pin without room next to its neighbour joins it as "+n".
    private var slots: [FPinSlot] {
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        var slots: [FPinSlot] = []
        for pin in pins {
            let x = CGFloat(pin.pinX.timeIntervalSince(domain.lowerBound) / span) * plotWidth
            if let last = slots.indices.last, x - slots[last].x < Self.pinWidth {
                slots[last].events.append(pin)
            } else {
                slots.append(FPinSlot(x: x, lane: 0, events: [pin]))
            }
        }
        return slots
    }

    private var yDomain: ClosedRange<Double> {
        let values = samples.flatMap { [$0.sollPlan] + ($0.ist.map { [$0] } ?? []) }
        return ((values.min() ?? 16) - 1).rounded(.down)...((values.max() ?? 22) + 1).rounded(.up)
    }

    var body: some View {
        let slots = slots
        let selectedSlot = slots.first { $0.matches(pinID) }
        Chart {
            ForEach(areas) { area in
                RectangleMark(xStart: .value("Start", max(area.date, domain.lowerBound)), xEnd: .value("Ende", min(area.end!, domain.upperBound)))
                    .foregroundStyle(FColor.ok.opacity(GStyle.areaOpacity))
            }
            gap
            ForEach(samples, id: \.date) { sample in
                LineMark(x: .value("Zeit", sample.date), y: .value("°C", sample.sollPlan), series: .value("Serie", "Soll"))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(Color.secondary.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            ForEach(samples.filter { $0.ist != nil }, id: \.date) { sample in
                LineMark(x: .value("Zeit", sample.date), y: .value("°C", sample.ist!), series: .value("Serie", "Ist"))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(GStyle.istLine)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            if let selectedSlot {
                ForEach(selectedSlot.events) { pin in
                    RuleMark(x: .value("Zeit", pin.pinX))
                        .foregroundStyle(Color.secondary.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                }
            }
            ForEach(slots) { slot in
                RuleMark(x: .value("Zeit", slot.events[0].pinX), yStart: .value("°C", yDomain.upperBound), yEnd: .value("°C", yDomain.upperBound))
                    .foregroundStyle(Color.clear)
                    .annotation(position: .top, spacing: 6, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        GPin(slot: slot, isSelected: slot.id == selectedSlot?.id)
                    }
            }
            if let crosshair {
                let sample = room.sample(at: crosshair)
                RuleMark(x: .value("Zeit", crosshair))
                    .foregroundStyle(Color.secondary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                if let ist = sample.ist {
                    PointMark(x: .value("Zeit", sample.date), y: .value("°C", ist))
                        .foregroundStyle(GStyle.istLine)
                        .symbolSize(40)
                }
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: yDomain)
        .chartLegend(.hidden)
        .chartXAxis { gTimeAxis(range) }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(GStyle.soft)
                AxisValueLabel { gYLabel("\(value.as(Double.self).map { Int($0) } ?? 0)°") }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let plotAnchor = proxy.plotFrame {
                    let plot = geo[plotAnchor]
                    ZStack(alignment: .topLeading) {
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                                if drag.startLocation.y < plot.minY {
                                    selectSlot(near: drag.startLocation.x - plot.minX, in: slots, proxy: proxy)
                                } else if let date: Date = proxy.value(atX: drag.location.x - plot.minX) {
                                    crosshair = min(max(date, domain.lowerBound), domain.upperBound)
                                }
                            })
                            .onContinuousHover { phase in
                                if case .active(let point) = phase, point.y >= plot.minY,
                                   let date: Date = proxy.value(atX: point.x - plot.minX) {
                                    crosshair = min(max(date, domain.lowerBound), domain.upperBound)
                                } else {
                                    crosshair = nil
                                }
                            }
                        if !hasIst {
                            Text("Keine Daten im Zeitraum")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .position(x: plot.midX, y: plot.midY)
                        }
                        if let slot = selectedSlot, let x = proxy.position(forX: slot.events[0].pinX) {
                            GPopover(events: slot.events)
                                .frame(width: Self.popoverWidth)
                                .fixedSize(horizontal: false, vertical: true)
                                .offset(x: popoverX(plot.minX + x, in: plot) - Self.popoverWidth / 2, y: plot.minY + 6)
                        }
                    }
                }
            }
        }
        .padding(.top, Self.rowHeight + 4)
        .frame(height: 210 + Self.rowHeight)
    }

    @ChartContentBuilder
    private var gap: some ChartContent {
        ForEach([("kalt", FColor.cold, GStyle.gapOpacity.cold), ("ok", FColor.ok, GStyle.gapOpacity.ok), ("warm", FColor.warm, GStyle.gapOpacity.warm)], id: \.0) { name, color, opacity in
            ForEach(samples.filter { $0.ist != nil }, id: \.date) { sample in
                let ist = sample.ist!
                let matches = FColor.delta(ist - sample.sollPlan) == color
                AreaMark(
                    x: .value("Zeit", sample.date),
                    yStart: .value("°C", ist),
                    yEnd: .value("°C", matches ? sample.sollPlan : ist),
                    series: .value("Lücke", name)
                )
                .foregroundStyle(gapStyle(name, color, opacity))
            }
        }
    }

    private func selectSlot(near x: CGFloat, in slots: [FPinSlot], proxy: ChartProxy) {
        let distance = { (slot: FPinSlot) in abs((proxy.position(forX: slot.events[0].pinX) ?? .infinity) - x) }
        guard let nearest = slots.min(by: { distance($0) < distance($1) }), distance(nearest) < Self.pinWidth else { return }
        pinID = nearest.matches(pinID) ? nil : nearest.id
    }

    private func popoverX(_ x: CGFloat, in plot: CGRect) -> CGFloat {
        let width = Self.popoverWidth
        let centre = x > plot.midX ? x - 10 - width / 2 : x + 10 + width / 2
        return min(max(centre, plot.minX + width / 2), plot.maxX - width / 2)
    }
}

/// A quiet pin: the symbol alone in secondary, primary while selected; "+n" for a group.
struct GPin: View {
    let slot: FPinSlot
    @Environment(\.fireplaceOn) private var fireplaceOn
    var isSelected = false

    var body: some View {
        Group {
            if slot.events.count > 1 {
                // H: a group holding the running fireplace keeps the flame visible.
                HStack(spacing: 2) {
                    if fireplaceOn == true, slot.events.contains(where: { $0.kind == .fireplace }) {
                        Image(systemName: "flame.fill").font(.caption2).foregroundStyle(.orange)
                    }
                    Text("+\(slot.events.count)").font(.caption2.weight(.semibold)).monospacedDigit()
                }
            } else {
                Image(systemName: slot.events[0].kind.symbol).font(.caption)
            }
        }
        .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .frame(minWidth: 16, minHeight: 16)
        .background(isSelected ? GStyle.soft : .clear, in: .capsule)
    }
}

/// Soft popover: raised fill and shadow, no border.
struct GPopover: View {
    let events: [FEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                VStack(alignment: .leading, spacing: 2) {
                    Label {
                        Text(event.kind.label + " · " + V3Fmt.dayTime(event.date) + (event.end.map { $0 >= FData.now ? " – jetzt" : " – \(Fmt.time($0))" } ?? ""))
                            .monospacedDigit()
                    } icon: {
                        Image(systemName: event.kind.symbol)
                    }
                    .labelStyle(FCompactLabel())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Text(event.title)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
        .shadow(color: .black.opacity(0.14), radius: 10, y: 3)
    }
}

struct GValveChart: View {
    let room: FRoom
    let range: FRange
    let samples: [FSample]
    let areas: [FEvent]
    @Binding var crosshair: Date?

    private var domain: ClosedRange<Date> { range.domain }
    private var hasValves: Bool { samples.contains { $0.valves.contains { $0 != nil } } }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if let crosshair {
                    let sample = room.sample(at: crosshair)
                    Text("Ventil · " + room.radiators.indices.map { "\(room.radiators[$0]) \(sample.valves[$0].map { "\(Int($0)) %" } ?? "–")" }.joined(separator: " · "))
                } else {
                    Text("Ventil")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()

            Chart {
                ForEach(areas) { area in
                    RectangleMark(xStart: .value("Start", max(area.date, domain.lowerBound)), xEnd: .value("Ende", min(area.end!, domain.upperBound)))
                        .foregroundStyle(FColor.ok.opacity(GStyle.areaOpacity))
                }
                ForEach(Array(room.radiators.enumerated()), id: \.offset) { index, radiator in
                    ForEach(samples.filter { $0.valves[index] != nil }, id: \.date) { sample in
                        AreaMark(x: .value("Zeit", sample.date), y: .value("%", sample.valves[index]!), series: .value("Heizkörper", radiator))
                            .interpolationMethod(.stepEnd)
                            .foregroundStyle(FColor.valve[index % FColor.valve.count].opacity(index == 0 ? 0.35 : 0.2))
                    }
                }
                if let crosshair {
                    RuleMark(x: .value("Zeit", crosshair))
                        .foregroundStyle(Color.secondary.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            .chartXScale(domain: domain)
            .chartYScale(domain: 0...100)
            .chartLegend(.hidden)
            .chartPlotStyle { $0.clipped() }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: [0, 100]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(GStyle.soft)
                    AxisValueLabel { gYLabel("\(value.as(Int.self) ?? 0) %") }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    if let plotAnchor = proxy.plotFrame {
                        let plot = geo[plotAnchor]
                        ZStack {
                            Rectangle().fill(.clear).contentShape(Rectangle())
                                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                                    if let date: Date = proxy.value(atX: drag.location.x - plot.minX) {
                                        crosshair = min(max(date, domain.lowerBound), domain.upperBound)
                                    }
                                })
                            if !hasValves {
                                Text("Keine Daten im Zeitraum")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .position(x: plot.midX, y: plot.midY)
                            }
                        }
                    }
                }
            }
            .frame(height: 56)
        }
    }
}

// MARK: - Week heatmap

struct GWeekHeatmap: View {
    let selectedRoomID: String?
    @Binding var cellID: String?

    private let rooms = FData.sortedRooms
    private let labelWidth: CGFloat = 52

    private var selectedCell: FCell? { FData.heatmap.first { $0.id == cellID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 3) {
                HStack(spacing: 0) {
                    Color.clear.frame(width: labelWidth, height: 1)
                    ForEach(FData.heatmapDays, id: \.self) { day in
                        Text(day.formatted(.dateTime.weekday(.short).locale(Fmt.de)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(rooms) { room in
                    HStack(spacing: 0) {
                        Text(room.short)
                            .font(.caption)
                            .fontWeight(room.id == selectedRoomID ? .semibold : .regular)
                            .foregroundStyle(room.id == selectedRoomID ? .primary : .secondary)
                            .lineLimit(1)
                            .frame(width: labelWidth, alignment: .leading)
                        ForEach(FData.heatmapDays, id: \.self) { day in
                            HStack(spacing: 2) {
                                ForEach(FData.heatmap.filter { $0.roomID == room.id && $0.day == day }.sorted { $0.segment < $1.segment }) { cell in
                                    cellView(cell)
                                }
                            }
                            .padding(.horizontal, 2.5)
                        }
                    }
                }
            }
            if let cell = selectedCell, let room = rooms.first(where: { $0.id == cell.roomID }) {
                HStack(spacing: 4) {
                    Text("\(room.name) · \(cell.day.formatted(.dateTime.weekday(.wide).locale(Fmt.de))) \(cell.segmentLabel)")
                        .foregroundStyle(.secondary)
                    Text(cell.delta.map(V3Fmt.kelvin) ?? "kein Ist-Wert")
                        .fontWeight(.semibold)
                        .foregroundStyle(cell.delta.map(FColor.delta) ?? .secondary)
                }
                .font(.caption)
                .monospacedDigit()
            }
        }
    }

    private func cellView(_ cell: FCell) -> some View {
        let isSelected = cell.id == cellID
        return Group {
            if let delta = cell.delta {
                RoundedRectangle(cornerRadius: 4).fill(FColor.heat(delta))
            } else {
                FHatch(showsMark: false).clipShape(.rect(cornerRadius: 4)).opacity(0.6)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 18)
        // Selected cell lifts slightly instead of getting a frame.
        .scaleEffect(isSelected ? 1.25 : 1)
        .shadow(color: .black.opacity(isSelected ? 0.25 : 0), radius: 3, y: 1)
        .zIndex(isSelected ? 1 : 0)
        .contentShape(Rectangle())
        .onTapGesture { cellID = isSelected ? nil : cell.id }
        .onHover { inside in cellID = inside ? cell.id : nil }
    }
}

// MARK: - Previews

private extension View {
    func gPreview(_ layout: FLayout, _ scheme: ColorScheme) -> some View {
        frame(width: layout == .compact ? FLayout.compactWidth : FLayout.regularWidth)
            .environment(\.colorScheme, scheme)
            .environment(\.locale, Fmt.de)
        #if os(macOS)
            .environment(\.controlActiveState, .key)
        #endif
    }
}

/// Opens G in a scenario for live checks outside previews (Mac window, iOS host app).
public struct LightScenarioView: View {
    let scenario: String
    let regular: Bool

    public init(scenario: String, regular: Bool) {
        self.scenario = scenario
        self.regular = regular
    }

    public var body: some View {
        let layout: FLayout = regular ? .regular : .compact
        switch scenario {
        case "hover": GScenario.hover24h(layout)
        case "auswahl": GScenario.selected(layout)
        default: GScenario.overview(layout)
        }
    }
}

private enum GScenario {
    static let arbeitPin = FData.room("arbeitszimmer").events.last { $0.kind == .observed }?.id
    static let schlafCell = FData.heatmap.first { $0.roomID == "schlafzimmer" && $0.day == FData.d(13, "00:00") && $0.segment == 1 }?.id

    /// First glance: nothing selected, no numbers but the headline.
    static func overview(_ layout: FLayout) -> LightVariant { LightVariant(layout: layout) }

    /// Bar tapped: pill on the name, headline stays, detail open without crosshair.
    static func selected(_ layout: FLayout) -> LightVariant { LightVariant(layout: layout, selectedRoomID: "bad-og", range: .day) }

    /// Hover everywhere: callout over the headline, crosshair values in the detail header, pin popover.
    static func hover24h(_ layout: FLayout) -> LightVariant {
        LightVariant(layout: layout, selectedRoomID: "arbeitszimmer", hoveredRoomID: "bad-og", range: .day, pinID: arbeitPin, crosshair: FData.d(15, "18:30"))
    }

    static func week(_ layout: FLayout) -> LightVariant {
        LightVariant(layout: layout, selectedRoomID: "schlafzimmer", range: .week, heatmapCellID: schlafCell)
    }

    static func noData(_ layout: FLayout) -> LightVariant { LightVariant(layout: layout, selectedRoomID: "kaminzimmer", range: .day) }
}

// H: fireplace switch placement. Esszimmer selected (it has data) so overview marks and detail pin show together.
private enum HScenario {
    static func view(_ placement: FireplacePlacement, _ layout: FLayout, on: Bool) -> LightVariant {
        LightVariant(layout: layout, selectedRoomID: "esszimmer", range: .day, fireplace: placement, fireplaceOn: on)
    }
}

#Preview("H-A Zeile iphone hell an") { HScenario.view(.row, .compact, on: true).gPreview(.compact, .light) }
#Preview("H-A Zeile iphone dunkel an") { HScenario.view(.row, .compact, on: true).gPreview(.compact, .dark) }
#Preview("H-A Zeile mac hell an") { HScenario.view(.row, .regular, on: true).gPreview(.regular, .light) }
#Preview("H-A Zeile mac dunkel an") { HScenario.view(.row, .regular, on: true).gPreview(.regular, .dark) }
#Preview("H-A Zeile iphone hell aus") { HScenario.view(.row, .compact, on: false).gPreview(.compact, .light) }
#Preview("H-A Zeile iphone dunkel aus") { HScenario.view(.row, .compact, on: false).gPreview(.compact, .dark) }
#Preview("H-A Zeile mac hell aus") { HScenario.view(.row, .regular, on: false).gPreview(.regular, .light) }
#Preview("H-A Zeile mac dunkel aus") { HScenario.view(.row, .regular, on: false).gPreview(.regular, .dark) }

#Preview("H-B Flamme iphone hell an") { HScenario.view(.headlineButton, .compact, on: true).gPreview(.compact, .light) }
#Preview("H-B Flamme iphone dunkel an") { HScenario.view(.headlineButton, .compact, on: true).gPreview(.compact, .dark) }
#Preview("H-B Flamme mac hell an") { HScenario.view(.headlineButton, .regular, on: true).gPreview(.regular, .light) }
#Preview("H-B Flamme mac dunkel an") { HScenario.view(.headlineButton, .regular, on: true).gPreview(.regular, .dark) }
#Preview("H-B Flamme iphone hell aus") { HScenario.view(.headlineButton, .compact, on: false).gPreview(.compact, .light) }
#Preview("H-B Flamme iphone dunkel aus") { HScenario.view(.headlineButton, .compact, on: false).gPreview(.compact, .dark) }
#Preview("H-B Flamme mac hell aus") { HScenario.view(.headlineButton, .regular, on: false).gPreview(.regular, .light) }
#Preview("H-B Flamme mac dunkel aus") { HScenario.view(.headlineButton, .regular, on: false).gPreview(.regular, .dark) }

#Preview("H-C Detailkopf iphone hell an") { HScenario.view(.detailHeader, .compact, on: true).gPreview(.compact, .light) }
#Preview("H-C Detailkopf iphone dunkel an") { HScenario.view(.detailHeader, .compact, on: true).gPreview(.compact, .dark) }
#Preview("H-C Detailkopf mac hell an") { HScenario.view(.detailHeader, .regular, on: true).gPreview(.regular, .light) }
#Preview("H-C Detailkopf mac dunkel an") { HScenario.view(.detailHeader, .regular, on: true).gPreview(.regular, .dark) }
#Preview("H-C Detailkopf iphone hell aus") { HScenario.view(.detailHeader, .compact, on: false).gPreview(.compact, .light) }
#Preview("H-C Detailkopf iphone dunkel aus") { HScenario.view(.detailHeader, .compact, on: false).gPreview(.compact, .dark) }
#Preview("H-C Detailkopf mac hell aus") { HScenario.view(.detailHeader, .regular, on: false).gPreview(.regular, .light) }
#Preview("H-C Detailkopf mac dunkel aus") { HScenario.view(.detailHeader, .regular, on: false).gPreview(.regular, .dark) }

#Preview("H-D Toolbar iphone hell an") { HScenario.view(.toolbar, .compact, on: true).gPreview(.compact, .light) }
#Preview("H-D Toolbar iphone dunkel an") { HScenario.view(.toolbar, .compact, on: true).gPreview(.compact, .dark) }
#Preview("H-D Toolbar mac hell an") { HScenario.view(.toolbar, .regular, on: true).gPreview(.regular, .light) }
#Preview("H-D Toolbar mac dunkel an") { HScenario.view(.toolbar, .regular, on: true).gPreview(.regular, .dark) }
#Preview("H-D Toolbar iphone hell aus") { HScenario.view(.toolbar, .compact, on: false).gPreview(.compact, .light) }
#Preview("H-D Toolbar iphone dunkel aus") { HScenario.view(.toolbar, .compact, on: false).gPreview(.compact, .dark) }
#Preview("H-D Toolbar mac hell aus") { HScenario.view(.toolbar, .regular, on: false).gPreview(.regular, .light) }
#Preview("H-D Toolbar mac dunkel aus") { HScenario.view(.toolbar, .regular, on: false).gPreview(.regular, .dark) }

#Preview("G iphone hell uebersicht") { GScenario.overview(.compact).gPreview(.compact, .light) }
#Preview("G iphone dunkel uebersicht") { GScenario.overview(.compact).gPreview(.compact, .dark) }
#Preview("G mac hell uebersicht") { GScenario.overview(.regular).gPreview(.regular, .light) }
#Preview("G mac dunkel uebersicht") { GScenario.overview(.regular).gPreview(.regular, .dark) }

#Preview("G iphone hell auswahl") { GScenario.selected(.compact).gPreview(.compact, .light) }
#Preview("G iphone dunkel auswahl") { GScenario.selected(.compact).gPreview(.compact, .dark) }
#Preview("G mac hell auswahl") { GScenario.selected(.regular).gPreview(.regular, .light) }
#Preview("G mac dunkel auswahl") { GScenario.selected(.regular).gPreview(.regular, .dark) }

#Preview("G iphone hell detail 24h hover") { GScenario.hover24h(.compact).gPreview(.compact, .light) }
#Preview("G iphone dunkel detail 24h hover") { GScenario.hover24h(.compact).gPreview(.compact, .dark) }
#Preview("G mac hell detail 24h hover") { GScenario.hover24h(.regular).gPreview(.regular, .light) }
#Preview("G mac dunkel detail 24h hover") { GScenario.hover24h(.regular).gPreview(.regular, .dark) }

#Preview("G iphone hell detail 7t") { GScenario.week(.compact).gPreview(.compact, .light) }
#Preview("G iphone dunkel detail 7t") { GScenario.week(.compact).gPreview(.compact, .dark) }
#Preview("G mac hell detail 7t") { GScenario.week(.regular).gPreview(.regular, .light) }
#Preview("G mac dunkel detail 7t") { GScenario.week(.regular).gPreview(.regular, .dark) }

#Preview("G iphone hell raum ohne daten") { GScenario.noData(.compact).gPreview(.compact, .light) }
#Preview("G iphone dunkel raum ohne daten") { GScenario.noData(.compact).gPreview(.compact, .dark) }
#Preview("G mac hell raum ohne daten") { GScenario.noData(.regular).gPreview(.regular, .light) }
#Preview("G mac dunkel raum ohne daten") { GScenario.noData(.regular).gPreview(.regular, .dark) }

#Preview("G iphone hell server nicht erreichbar") { LightVariant(layout: .compact, loadState: .serverUnreachable).gPreview(.compact, .light) }
#Preview("G iphone dunkel server nicht erreichbar") { LightVariant(layout: .compact, loadState: .serverUnreachable).gPreview(.compact, .dark) }
#Preview("G mac hell server nicht erreichbar") { LightVariant(layout: .regular, loadState: .serverUnreachable).gPreview(.regular, .light) }
#Preview("G mac dunkel server nicht erreichbar") { LightVariant(layout: .regular, loadState: .serverUnreachable).gPreview(.regular, .dark) }

#Preview("G iphone hell keine raeume") { LightVariant(layout: .compact, loadState: .noRooms).gPreview(.compact, .light) }
#Preview("G iphone dunkel keine raeume") { LightVariant(layout: .compact, loadState: .noRooms).gPreview(.compact, .dark) }
#Preview("G mac hell keine raeume") { LightVariant(layout: .regular, loadState: .noRooms).gPreview(.regular, .light) }
#Preview("G mac dunkel keine raeume") { LightVariant(layout: .regular, loadState: .noRooms).gPreview(.regular, .dark) }
