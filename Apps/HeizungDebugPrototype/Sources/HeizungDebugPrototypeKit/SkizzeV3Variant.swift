import Charts
import SwiftUI

/// Variant E, "Skizze v3": Δ bars per room first; a tap opens Soll/Ist with event pins and
/// the valve chart below; the week heatmap shows patterns. Everything is read off the charts,
/// no "why" line, no chips, no decision list.
struct SkizzeV3Variant: View {
    @State var selectedRoomID: String?
    @State var range: V3Range = .day
    @State var pinID: String?
    @State var crosshair: Date?

    var body: some View {
        Screen(title: "Heizung", subtitle: "Δ = Ist − Soll je Raum, jetzt · kältester links") {
            Card {
                DeltaBarChart(selectedRoomID: Binding(
                    get: { selectedRoomID },
                    set: { selectedRoomID = $0; pinID = nil; crosshair = nil }
                ))
            }
            if let room = selectedRoomID.map(V3Data.room) {
                Card {
                    RoomDetail(room: room, range: $range, pinID: $pinID, crosshair: $crosshair) {
                        selectedRoomID = nil
                    }
                }
            }
            Card(title: "Woche: Δ je Raum × Stunde (7 T)") {
                WeekHeatmap(selectedRoomID: selectedRoomID, crosshair: crosshair) { roomID, hour in
                    selectedRoomID = roomID
                    pinID = nil
                    crosshair = hour.addingTimeInterval(1_800)
                    range = hour < V3Data.now.addingTimeInterval(-86_400) ? .week : .day
                }
            }
        }
    }
}

// MARK: - Formatting

enum V3Fmt {
    static func kelvin(_ value: Double) -> String {
        let number = abs(value).formatted(.number.precision(.fractionLength(1)).locale(Fmt.de))
        return (value >= 0.05 ? "+" : value <= -0.05 ? "−" : "±") + number + " K"
    }

    static func deg(_ value: Double?) -> String {
        guard let value else { return "–" }
        return value.formatted(.number.precision(.fractionLength(1)).locale(Fmt.de)) + "°"
    }

    static func dayTime(_ date: Date) -> String {
        Calendar.current.isDate(date, inSameDayAs: V3Data.now)
            ? Fmt.time(date)
            : date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).locale(Fmt.de)) + " " + Fmt.time(date)
    }

    static func deltaColor(_ delta: Double) -> Color {
        delta < 0 ? .blue : .orange
    }
}

// MARK: - ① Δ bars

struct DeltaBarChart: View {
    @Binding var selectedRoomID: String?

    private let rooms = V3Data.sortedRooms
    private let limit = 3.0

    private var selected: V3Room? { rooms.first { $0.id == selectedRoomID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                RectangleMark(yStart: .value("Δ", -0.5), yEnd: .value("Δ", 0.5))
                    .foregroundStyle(Color.gray.opacity(0.16))
                RuleMark(y: .value("Δ", 0))
                    .foregroundStyle(Color.primary.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                ForEach(rooms) { room in
                    if let delta = room.delta {
                        let clamped = min(max(delta, -limit), limit)
                        let isSelected = room.id == selectedRoomID
                        BarMark(x: .value("Raum", room.short), y: .value("Δ", clamped), width: .ratio(0.62))
                            .foregroundStyle(V3Fmt.deltaColor(delta).opacity(selectedRoomID == nil || isSelected ? 0.85 : 0.35))
                            .annotation(position: delta < 0 ? .bottom : .top, spacing: 3) {
                                Text(V3Fmt.kelvin(delta).replacingOccurrences(of: " K", with: ""))
                                    .font(.caption2.monospacedDigit().weight(isSelected ? .bold : .regular))
                                    .foregroundStyle(.secondary)
                            }
                    } else {
                        // Keeps the category on the axis; the hatched box is drawn in the overlay.
                        BarMark(x: .value("Raum", room.short), yStart: .value("Δ", -0.6), yEnd: .value("Δ", 0.6), width: .ratio(0.62))
                            .foregroundStyle(Color.clear)
                    }
                }
                if let selected {
                    let tip = min(max(selected.delta ?? 0, -limit), limit)
                    RuleMark(x: .value("Raum", selected.short), yStart: .value("Δ", tip), yEnd: .value("Δ", limit + 0.6))
                        .foregroundStyle(Color.blue.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            LollipopCallout(room: selected)
                        }
                    if selected.delta != nil {
                        PointMark(x: .value("Raum", selected.short), y: .value("Δ", tip))
                            .foregroundStyle(Color.blue)
                            .symbolSize(40)
                    }
                }
            }
            .chartYScale(domain: -(limit + 0.6)...(limit + 0.6))
            .chartYAxis {
                AxisMarks(position: .leading, values: [-3.0, 0, 3.0]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    AxisValueLabel {
                        let number = value.as(Double.self) ?? 0
                        Text(number == 0 ? "0" : number > 0 ? "+3" : "−3")
                    }
                }
            }
            .chartXAxis {
                AxisMarks { _ in AxisValueLabel() }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        missingSensorBoxes(proxy: proxy, geo: geo)
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .gesture(SpatialTapGesture().onEnded { tap in
                                guard let plot = proxy.plotFrame else { return }
                                let x = tap.location.x - geo[plot].minX
                                guard let short: String = proxy.value(atX: x),
                                      let room = rooms.first(where: { $0.short == short }) else { return }
                                selectedRoomID = selectedRoomID == room.id ? nil : room.id
                            })
                    }
                }
            }
            .padding(.top, selected == nil ? 4 : 44)
            .frame(height: selected == nil ? 230 : 270)

            HStack(spacing: 12) {
                legendSwatch(Color.gray.opacity(0.25), "±0,5 K = ok")
                legendSwatch(.blue.opacity(0.85), "zu kalt")
                legendSwatch(.orange.opacity(0.85), "zu warm")
                HStack(spacing: 4) {
                    HatchBox(showsMark: false).frame(width: 12, height: 10)
                    Text("kein Wert")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func missingSensorBoxes(proxy: ChartProxy, geo: GeometryProxy) -> some View {
        if let plot = proxy.plotFrame {
            let frame = geo[plot]
            ForEach(rooms.filter { $0.delta == nil }) { room in
                if let x = proxy.position(forX: room.short),
                   let top = proxy.position(forY: 0.6),
                   let bottom = proxy.position(forY: -0.6) {
                    let width = frame.width / CGFloat(rooms.count) * 0.62
                    HatchBox(isSelected: room.id == selectedRoomID)
                        .frame(width: width, height: bottom - top)
                        .position(x: frame.minX + x, y: frame.minY + (top + bottom) / 2)
                }
            }
        }
    }

    private func legendSwatch(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: 10)
            Text(label)
        }
    }
}

/// Room without a working sensor: outlined, hatched, "?".
struct HatchBox: View {
    var isSelected = false
    var showsMark = true

    var body: some View {
        ZStack {
            Canvas { context, size in
                var path = Path()
                var x = -size.height
                while x < size.width {
                    path.move(to: CGPoint(x: x, y: size.height))
                    path.addLine(to: CGPoint(x: x + size.height, y: 0))
                    x += 5
                }
                context.stroke(path, with: .color(.gray.opacity(0.5)), lineWidth: 1)
            }
            .clipShape(.rect)
            Rectangle()
                .strokeBorder(isSelected ? Color.blue : .gray, style: StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: [3, 2]))
            if showsMark {
                Text("?").font(.headline.bold()).foregroundStyle(.primary)
            }
        }
    }
}

struct LollipopCallout: View {
    let room: V3Room

    var body: some View {
        Group {
            if let delta = room.delta {
                Text("**\(room.name) \(V3Fmt.kelvin(delta))** · Ist \(V3Fmt.deg(room.current.ist)) / Soll \(V3Fmt.deg(room.current.soll))")
            } else {
                let last = room.lastIst
                Text("**\(room.name) ?** · Ist – (letzter Wert \(last.map { V3Fmt.dayTime($0.date) } ?? "–")) / Soll \(V3Fmt.deg(room.current.soll))")
            }
        }
        .font(.caption)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white, in: .rect(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.blue.opacity(0.6)))
        .fixedSize()
    }
}

// MARK: - ④ Detail

struct RoomDetail: View {
    let room: V3Room
    @Binding var range: V3Range
    @Binding var pinID: String?
    @Binding var crosshair: Date?
    let onClose: () -> Void

    private var domain: ClosedRange<Date> { range.domain }

    /// 7 T keeps every third sample: enough for the shape, a third of the marks.
    private var samples: [V3Sample] {
        let visible = room.samples.filter { domain.contains($0.date) }
        return range == .week ? visible.enumerated().filter { $0.offset % 3 == 0 || $0.offset == visible.count - 1 }.map(\.element) : visible
    }

    /// Plan pins only up to 24 h; over a week they would bury the rest.
    private var pins: [V3Event] {
        room.events.compactMap { event in
            guard range != .week || event.kind != .plan else { return nil }
            if domain.contains(event.date) { return event }
            // A band that started before the range keeps its pin at the left edge.
            guard let end = event.end, end > domain.lowerBound, event.date < domain.lowerBound else { return nil }
            return event.pinned(at: domain.lowerBound)
        }
    }

    private var bands: [V3Event] {
        room.events.filter { event in
            guard let end = event.end else { return false }
            return end > domain.lowerBound && event.date < domain.upperBound
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Soll / Ist · \(room.name)").font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Picker("Zeitraum", selection: $range) {
                ForEach(V3Range.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: range) {
                pinID = nil
                if let date = crosshair, !domain.contains(date) { crosshair = nil }
            }

            SollIstChart(room: room, range: range, samples: samples, pins: pins, bands: bands, pinID: $pinID, crosshair: $crosshair)
            EventLegend()

            Text("Ventil je Heizkörper").font(.subheadline.weight(.semibold)).padding(.top, 4)
            ValveStepChart(room: room, range: range, samples: samples, pins: pins, bands: bands, crosshair: $crosshair)
        }
    }

    private var subtitle: String {
        var parts = [room.thermo]
        parts += room.windowContacts
        if let down = room.sensorDownSince {
            parts.append("still seit \(V3Fmt.dayTime(down))")
        }
        return parts.joined(separator: " · ")
    }
}

/// Time axis shared by Soll/Ist and valve, so both charts line up.
func v3TimeAxis(_ range: V3Range) -> some AxisContent {
    let (component, count): (Calendar.Component, Int) = switch range {
    case .twoHours: (.minute, 30)
    case .day: (.hour, 4)
    case .week: (.day, 1)
    }
    return AxisMarks(values: .stride(by: component, count: count)) { value in
        AxisGridLine()
        AxisValueLabel(centered: range == .week) {
            if let date = value.as(Date.self) {
                Text(range == .week ? date.formatted(.dateTime.weekday(.abbreviated).locale(Fmt.de)) : Fmt.time(date))
            }
        }
    }
}

/// ⑤ ⑥ Soll dashed step, Ist solid, the gap shaded; pins above the plot.
struct SollIstChart: View {
    let room: V3Room
    let range: V3Range
    let samples: [V3Sample]
    let pins: [V3Event]
    let bands: [V3Event]
    @Binding var pinID: String?
    @Binding var crosshair: Date?

    private static let laneHeight: CGFloat = 22
    private static let pinWidth: CGFloat = 20

    private var domain: ClosedRange<Date> { range.domain }

    /// Stacks pins that would overlap: each pin takes the lowest lane that is free at its x.
    private var lanes: [String: Int] {
        let plotWidth: CGFloat = 330
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        var lastX: [CGFloat] = []
        var result: [String: Int] = [:]
        for pin in pins {
            let x = CGFloat(pin.pinX.timeIntervalSince(domain.lowerBound) / span) * plotWidth
            let lane = lastX.firstIndex { x - $0 >= Self.pinWidth } ?? lastX.count
            if lane == lastX.count { lastX.append(x) } else { lastX[lane] = x }
            result[pin.id] = lane
        }
        return result
    }

    private var laneCount: Int { (lanes.values.max() ?? -1) + 1 }

    private var yDomain: ClosedRange<Double> {
        let values = samples.flatMap { [$0.soll] + ($0.ist.map { [$0] } ?? []) }
        let low = ((values.min() ?? 16) - 1).rounded(.down)
        let high = ((values.max() ?? 22) + 1).rounded(.up)
        return low...high
    }

    private var selectedPin: V3Event? { pins.first { $0.id == pinID } }

    var body: some View {
        let lanes = lanes
        Chart {
            ForEach(bands) { band in
                RectangleMark(
                    xStart: .value("Start", max(band.date, domain.lowerBound)),
                    xEnd: .value("Ende", min(band.end!, domain.upperBound))
                )
                .foregroundStyle(band.kind.color.opacity(0.13))
            }
            if let down = room.sensorDownSince, down < domain.upperBound {
                RectangleMark(xStart: .value("Start", max(down, domain.lowerBound)), xEnd: .value("Ende", domain.upperBound))
                    .foregroundStyle(Color.gray.opacity(0.12))
                    .annotation(position: .overlay, alignment: .center) {
                        Text("kein Ist-Wert seit \(V3Fmt.dayTime(down))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.9), in: .capsule)
                    }
            }
            ForEach(samples, id: \.date) { sample in
                if let ist = sample.ist {
                    AreaMark(x: .value("Zeit", sample.date), yStart: .value("°C", ist), yEnd: .value("°C", max(ist, sample.soll)), series: .value("Lücke", "kalt"))
                        .foregroundStyle(Color.blue.opacity(0.16))
                    AreaMark(x: .value("Zeit", sample.date), yStart: .value("°C", sample.soll), yEnd: .value("°C", max(ist, sample.soll)), series: .value("Lücke", "warm"))
                        .foregroundStyle(Color.orange.opacity(0.22))
                }
            }
            ForEach(samples, id: \.date) { sample in
                LineMark(x: .value("Zeit", sample.date), y: .value("°C", sample.soll), series: .value("Serie", "Soll"))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
            }
            ForEach(samples.filter { $0.ist != nil }, id: \.date) { sample in
                LineMark(x: .value("Zeit", sample.date), y: .value("°C", sample.ist!), series: .value("Serie", "Ist"))
                    .foregroundStyle(Color.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            ForEach(pins) { pin in
                let isSelected = pin.id == pinID
                RuleMark(x: .value("Zeit", pin.pinX))
                    .foregroundStyle(pin.kind.color.opacity(isSelected ? 0.9 : 0.45))
                    .lineStyle(StrokeStyle(lineWidth: isSelected ? 1.5 : 1, dash: [2, 2]))
                    .annotation(position: .top, spacing: 3 + CGFloat(lanes[pin.id] ?? 0) * Self.laneHeight, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        PinBadge(kind: pin.kind, isSelected: isSelected)
                    }
            }
            if let crosshair {
                let sample = room.sample(at: crosshair)
                RuleMark(x: .value("Zeit", crosshair))
                    .foregroundStyle(Color.blue.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("Zeit", sample.date), y: .value("°C", sample.soll))
                    .foregroundStyle(Color.primary)
                    .symbolSize(30)
                if let ist = sample.ist {
                    PointMark(x: .value("Zeit", sample.date), y: .value("°C", ist))
                        .foregroundStyle(Color.blue)
                        .symbolSize(30)
                }
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: yDomain)
        .chartLegend(.hidden)
        .chartXAxis { v3TimeAxis(range) }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel { Text("\(value.as(Double.self).map { Int($0) } ?? 0)°") }
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
                                    selectPin(near: drag.startLocation.x - plot.minX, proxy: proxy)
                                } else if let date: Date = proxy.value(atX: drag.location.x - plot.minX) {
                                    crosshair = min(max(date, domain.lowerBound), domain.upperBound)
                                }
                            })
                        if let crosshair, let x = proxy.position(forX: crosshair) {
                            CrosshairLabel(room: room, date: crosshair)
                                .position(x: clamp(plot.minX + x, width: 170, in: plot), y: plot.maxY - 16)
                        }
                        if let pin = selectedPin, let x = proxy.position(forX: pin.pinX) {
                            PinPopover(event: pin)
                                .frame(width: 230)
                                .position(x: popoverX(plot.minX + x, width: 230, in: plot), y: plot.minY + 34)
                        }
                    }
                }
            }
        }
        .padding(.top, CGFloat(max(laneCount, 1)) * Self.laneHeight + 4)
        .frame(height: 230 + CGFloat(max(laneCount, 1)) * Self.laneHeight)
    }

    private func selectPin(near x: CGFloat, proxy: ChartProxy) {
        let nearest = pins.min { a, b in
            abs((proxy.position(forX: a.pinX) ?? .infinity) - x) < abs((proxy.position(forX: b.pinX) ?? .infinity) - x)
        }
        guard let nearest, let pinX = proxy.position(forX: nearest.pinX), abs(pinX - x) < Self.pinWidth else { return }
        pinID = pinID == nearest.id ? nil : nearest.id
    }
}

/// Centres a box of `width` at `x`, kept inside the plot.
private func clamp(_ x: CGFloat, width: CGFloat, in plot: CGRect) -> CGFloat {
    min(max(x, plot.minX + width / 2), plot.maxX - width / 2)
}

/// Hangs the popover beside its pin, on the side with more room, so the pin and the
/// latest values next to it stay visible.
private func popoverX(_ x: CGFloat, width: CGFloat, in plot: CGRect) -> CGFloat {
    let centre = x > plot.midX ? x - 8 - width / 2 : x + 8 + width / 2
    return clamp(centre, width: width, in: plot)
}

struct PinBadge: View {
    let kind: V3EventKind
    var isSelected = false

    var body: some View {
        Text(kind.emoji)
            .font(.system(size: 11))
            .frame(width: 18, height: 18)
            .background(Circle().fill(Color.white))
            .overlay(Circle().strokeBorder(kind.color.opacity(isSelected ? 1 : 0.6), lineWidth: isSelected ? 2 : 1))
    }
}

struct PinPopover: View {
    let event: V3Event

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(event.kind.emoji)
                Text(V3Fmt.dayTime(event.date) + (event.end.map { $0 >= V3Data.now ? " – jetzt" : " – \(Fmt.time($0))" } ?? ""))
                    .font(.caption.weight(.semibold).monospacedDigit())
            }
            Text(event.title).font(.caption).fixedSize(horizontal: false, vertical: true)
            Text(event.reason)
                .font(.caption2.monospaced())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .foregroundStyle(event.kind.color)
                .background(event.kind.color.opacity(0.14), in: .capsule)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(event.kind.color.opacity(0.7)))
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }
}

struct CrosshairLabel: View {
    let room: V3Room
    let date: Date

    var body: some View {
        let sample = room.sample(at: date)
        Text("\(V3Fmt.dayTime(sample.date)) · \(V3Fmt.deg(sample.ist)) / \(V3Fmt.deg(sample.soll)) · \(sample.valve.map { "\(Int($0)) %" } ?? "–")")
            .font(.caption2.monospacedDigit())
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.white, in: .rect(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.blue.opacity(0.6)))
            .fixedSize()
    }
}

struct EventLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Rectangle().stroke(style: StrokeStyle(lineWidth: 1.5, dash: [4, 2])).frame(width: 14, height: 0.1)
                    Text("Soll")
                }
                HStack(spacing: 4) {
                    Capsule().fill(Color.blue).frame(width: 14, height: 2.5)
                    Text("Ist")
                }
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.blue.opacity(0.2)).frame(width: 12, height: 10)
                    Text("Lücke")
                }
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.teal.opacity(0.25)).frame(width: 12, height: 10)
                    Text("Dauer (Fenster, Kamin)")
                }
            }
            HStack(spacing: 8) {
                ForEach(V3EventKind.allCases, id: \.self) { kind in
                    Text("\(kind.emoji) \(kind.label)")
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

/// ⑦ Valve % per radiator as step lines; same x-domain, event rules and crosshair.
struct ValveStepChart: View {
    let room: V3Room
    let range: V3Range
    let samples: [V3Sample]
    let pins: [V3Event]
    let bands: [V3Event]
    @Binding var crosshair: Date?

    private var domain: ClosedRange<Date> { range.domain }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Chart {
                ForEach(bands) { band in
                    RectangleMark(
                        xStart: .value("Start", max(band.date, domain.lowerBound)),
                        xEnd: .value("Ende", min(band.end!, domain.upperBound))
                    )
                    .foregroundStyle(band.kind.color.opacity(0.13))
                }
                ForEach(pins) { pin in
                    RuleMark(x: .value("Zeit", pin.pinX))
                        .foregroundStyle(pin.kind.color.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                }
                ForEach(samples.filter { $0.valve != nil }, id: \.date) { sample in
                    LineMark(x: .value("Zeit", sample.date), y: .value("%", sample.valve!), series: .value("Heizkörper", room.thermo))
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(Color.green)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
                if let crosshair {
                    RuleMark(x: .value("Zeit", crosshair))
                        .foregroundStyle(Color.blue.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
                if let crosshair, let valve = room.sample(at: crosshair).valve {
                    PointMark(x: .value("Zeit", room.sample(at: crosshair).date), y: .value("%", valve))
                        .foregroundStyle(Color.green)
                        .symbolSize(30)
                }
            }
            .chartXScale(domain: domain)
            .chartYScale(domain: 0...100)
            .chartXAxis { v3TimeAxis(range) }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel { Text("\(value.as(Int.self) ?? 0) %") }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    if let plotAnchor = proxy.plotFrame {
                        let plot = geo[plotAnchor]
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                                if let date: Date = proxy.value(atX: drag.location.x - plot.minX) {
                                    crosshair = min(max(date, domain.lowerBound), domain.upperBound)
                                }
                            })
                    }
                }
            }
            .frame(height: 100)

            HStack(spacing: 4) {
                Capsule().fill(Color.green).frame(width: 14, height: 2.5)
                Text("\(room.thermo) · jetzt " + (room.current.valve.map { "\(Int($0)) %" } ?? "kein Wert"))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - ⑧ Week heatmap

struct WeekHeatmap: View {
    let selectedRoomID: String?
    let crosshair: Date?
    let onSelect: (String, Date) -> Void

    private let rooms = V3Data.sortedRooms

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Numeric rows: categorical y bands collapse to hairlines next to a date x-axis.
            let rows = Double(rooms.count)
            Chart {
                ForEach(V3Data.heatmap) { cell in
                    let row = rows - Double(rowIndex(cell.roomID))
                    RectangleMark(
                        xStart: .value("Stunde", cell.hour),
                        xEnd: .value("Stunde", cell.hour.addingTimeInterval(3_600)),
                        yStart: .value("Reihe", row - 0.92),
                        yEnd: .value("Reihe", row - 0.08)
                    )
                    .foregroundStyle(color(cell.delta))
                }
                if let crosshair, selectedRoomID != nil {
                    RuleMark(x: .value("Zeit", crosshair))
                        .foregroundStyle(Color.primary.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            .chartXScale(domain: V3Data.weekStart...V3Data.now)
            .chartYScale(domain: 0...rows)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: rooms.indices.map { rows - Double($0) - 0.5 }) { value in
                    AxisValueLabel {
                        let index = Int(rows - (value.as(Double.self) ?? 0) - 0.5)
                        let room = rooms[min(max(index, 0), rooms.count - 1)]
                        Text(room.short).fontWeight(room.id == selectedRoomID ? .bold : .regular)
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    if let plotAnchor = proxy.plotFrame {
                        let plot = geo[plotAnchor]
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .gesture(SpatialTapGesture().onEnded { tap in
                                let point = CGPoint(x: tap.location.x - plot.minX, y: tap.location.y - plot.minY)
                                guard let (date, row) = proxy.value(at: point, as: (Date, Double).self) else { return }
                                let index = Int(rows - row)
                                guard rooms.indices.contains(index) else { return }
                                onSelect(rooms[index].id, Calendar.current.dateInterval(of: .hour, for: date)!.start)
                            })
                    }
                }
            }
            .frame(height: CGFloat(rooms.count) * 20 + 24)

            HStack(spacing: 6) {
                Text("−3 K")
                LinearGradient(colors: [.blue.opacity(0.9), .white, .orange.opacity(0.9)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 90, height: 8)
                    .clipShape(.capsule)
                Text("+3 K")
                RoundedRectangle(cornerRadius: 2).fill(Color.gray.opacity(0.3)).frame(width: 12, height: 8).padding(.leading, 8)
                Text("kein Wert")
                Spacer()
                Text("Tap → Raum + Zeitpunkt")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func rowIndex(_ roomID: String) -> Int {
        rooms.firstIndex { $0.id == roomID } ?? 0
    }

    private func color(_ delta: Double?) -> Color {
        guard let delta else { return .gray.opacity(0.3) }
        let strength = min(abs(delta) / 3, 1)
        // Inside the comfort band the cell stays almost white.
        let opacity = abs(delta) < 0.5 ? strength * 0.4 : 0.15 + strength * 0.8
        return V3Fmt.deltaColor(delta).opacity(opacity)
    }
}

// MARK: - Previews

#Preview("E Skizze v3 – Übersicht") {
    SkizzeV3Variant().environment(\.locale, Fmt.de)
}

#Preview("E Skizze v3 – Arbeitszimmer 24 h, Pin und Crosshair") {
    let pin = V3Data.room("arbeitszimmer").events.last { $0.kind == .manual }
    SkizzeV3Variant(
        selectedRoomID: "arbeitszimmer", range: .day, pinID: pin?.id,
        crosshair: V3Data.d(15, "18:30")
    )
    .environment(\.locale, Fmt.de)
}

#Preview("E Skizze v3 – Bad OG 24 h, Ventil hängt") {
    SkizzeV3Variant(selectedRoomID: "bad-og", range: .day, crosshair: V3Data.d(15, "19:00"))
        .environment(\.locale, Fmt.de)
}

#Preview("E Skizze v3 – Küche 7 T") {
    let pin = V3Data.room("kueche").events.last { $0.kind == .window }
    SkizzeV3Variant(selectedRoomID: "kueche", range: .week, pinID: pin?.id, crosshair: V3Data.d(13, "07:10"))
        .environment(\.locale, Fmt.de)
}

#Preview("E Skizze v3 – Kaminzimmer aus Heatmap, Sensor still") {
    SkizzeV3Variant(selectedRoomID: "kaminzimmer", range: .week, crosshair: V3Data.d(9, "20:30"))
        .environment(\.locale, Fmt.de)
}

#Preview("E Skizze v3 – Esszimmer 2 h, Kamin") {
    let pin = V3Data.room("esszimmer").events.last { $0.kind == .system }
    SkizzeV3Variant(selectedRoomID: "esszimmer", range: .twoHours, pinID: pin?.id, crosshair: V3Data.d(15, "21:30"))
        .environment(\.locale, Fmt.de)
}
