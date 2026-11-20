//
//  HeatingDetailView.swift
//  ControllerFeatures
//
//  The room detail in Variante G "Leicht": header, range switch, actual and plan chart, valve chart
//

import Charts
import HAModels
import SwiftUI

/// Rounded card of the Heizung tab.
struct HeatingCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(HeatingPalette.card(scheme)))
    }
}

struct HeatingRoomDetailView: View {
    let detail: HeatingRoomDetail
    @Binding var range: HeatingRange
    /// The pin (or "+n" group) whose reason is shown.
    var selectedPinId: String?
    var onSelectPin: (String?) -> Void = { _ in }
    /// Compact (iPhone): the reason is an inline card below the chart; regular (Mac, iPad): a popover at the pin.
    var layout: HeatingLayout = .regular
    /// Estimate of the plot width until the chart measured itself; the pins stack with it.
    var plotWidthEstimate: CGFloat = 290
    /// The selected moment of the crosshair; driven by hover or drag, preset in previews.
    @State var crosshair: Date?
    var onClose: (() -> Void)?

    @Environment(\.colorScheme) private var scheme

    private var shown: HeatingSample? {
        crosshair.flatMap { HeatingChartData.nearest(to: $0, in: detail.samples) } ?? detail.latest
    }

    private var includesDay: Bool { range == .week }

    private var selectedSlot: HeatingPinLayout.Slot? {
        HeatingSollIstChart.slots(events: detail.events, samples: detail.samples, range: range, plotWidth: plotWidthEstimate).first { $0.contains(selectedPinId) }
    }

    var body: some View {
        HeatingCard {
            VStack(alignment: .leading, spacing: 8) {
                header
                HeatingRangePicker(range: $range)
                    .padding(.bottom, 8)
                HeatingSollIstChart(samples: detail.samples, events: detail.events, crosshair: $crosshair, range: range,
                                    selectedPinId: selectedPinId, onSelectPin: onSelectPin, layout: layout, plotWidthEstimate: plotWidthEstimate)
                    .frame(height: 210 + HeatingSollIstChart.pinAreaHeight)
                    .overlay {
                        if detail.hasNoData {
                            Text("Keine Daten im Zeitraum")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                if layout == .compact, let slot = selectedSlot {
                    HeatingPinCard(events: slot.events)
                }
                if !detail.radiators.isEmpty {
                    valveHeader
                        .padding(.top, 8)
                    HeatingValveChart(samples: detail.samples, events: detail.events, radiators: detail.radiators, crosshair: $crosshair, range: range)
                        .frame(height: 56)
                        .overlay {
                            if !detail.hasValues {
                                Text("Keine Daten im Zeitraum")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                if crosshair != nil, let sample = shown {
                    Text("\(detail.name) · \(HeatingFormat.time(sample.date, includingDay: includesDay))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text(detail.name)
                        .font(.headline)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let ist = shown?.ist {
                        Text(HeatingFormat.degrees(ist))
                            .font(.largeTitle.weight(.semibold).monospacedDigit())
                    } else {
                        Text("Kein Ist-Wert")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    if let plan = shown?.sollPlan {
                        Text("Plan \(HeatingFormat.degrees(plan))")
                            .font(.title3.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if let delta = shown?.delta {
                        Text(HeatingFormat.kelvin(delta))
                            .font(.title3.weight(.semibold).monospacedDigit())
                            .foregroundStyle(HeatingPalette.color(forDelta: delta, scheme: scheme))
                    }
                }
                if crosshair != nil {
                    Label(sourceText, systemImage: sourceSymbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if shown?.ist == nil {
                    Text(lastIstText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let onClose {
                Button("Schließen", systemImage: "xmark.circle.fill", action: onClose)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .font(.title3)
            }
        }
    }

    private var lastIstText: String {
        guard let last = detail.lastIst else { return "bisher kein Ist-Wert" }
        return "kein Ist-Wert seit \(HeatingFormat.time(last, includingDay: true))"
    }

    private var sourceSymbol: String {
        switch detail.istSource {
        case .roomSensor: "thermometer.medium"
        case .thermostats: "heater.vertical"
        }
    }

    private var sourceText: String {
        switch detail.istSource {
        case .roomSensor(let name): "Raumsensor „\(name)“"
        case .thermostats: "Mittel der Thermostate"
        }
    }

    /// "Ventil", on hover the radiators with their values at that moment.
    private var valveHeader: some View {
        Group {
            if crosshair != nil, let sample = shown {
                let parts = detail.radiators.enumerated().map { index, name -> String in
                    let value = sample.valves.indices.contains(index) ? sample.valves[index] : nil
                    return "\(name) \(value.map(HeatingFormat.percent) ?? "–")"
                }
                Text("Ventil · " + parts.joined(separator: " · "))
            } else {
                Text("Ventil")
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }
}

/// Trailing labels of one width in both charts, so the plots and the crosshair line up.
private func heatingYLabel(_ text: String) -> some View {
    Text(text).font(.caption2.monospacedDigit()).lineLimit(1).fixedSize().frame(width: 36, alignment: .leading)
}

private let heatingGrid = Color.secondary.opacity(0.12)

/// Soft grey actual line, dashed plan line, colour only in the gap between them.
struct HeatingSollIstChart: View {
    let samples: [HeatingSample]
    var events: [HeatingEvent] = []
    @Binding var crosshair: Date?
    var range: HeatingRange = .day
    var selectedPinId: String?
    var onSelectPin: (String?) -> Void = { _ in }
    var layout: HeatingLayout = .regular
    var plotWidthEstimate: CGFloat = 290

    static let pinWidth: CGFloat = 22
    static let pinRowHeight: CGFloat = 22
    static let pinRows = 2
    /// Room above the plot for the pin rows.
    static let pinAreaHeight: CGFloat = pinRowHeight * CGFloat(pinRows) + 4

    /// Measured width of the plot; the estimate until the first layout.
    @State private var measuredWidth: CGFloat?

    static func slots(events: [HeatingEvent], samples: [HeatingSample], range: HeatingRange, plotWidth: CGFloat) -> [HeatingPinLayout.Slot] {
        HeatingPinLayout.slots(HeatingPinLayout.pins(events, range: range), in: HeatingChartData.timeDomain(samples), plotWidth: plotWidth, pinWidth: pinWidth, rows: pinRows)
    }

    private var slots: [HeatingPinLayout.Slot] {
        Self.slots(events: events, samples: samples, range: range, plotWidth: measuredWidth ?? plotWidthEstimate)
    }

    @Environment(\.colorScheme) private var scheme

    /// Light: strong at the actual line, fading towards the plan. Dark: a flat, higher opacity, so
    /// the peach orange does not turn brown on the dark card.
    private func gapStyle(_ band: HeatingComfort) -> AnyShapeStyle {
        let color = HeatingPalette.color(band, scheme: scheme)
        if scheme == .dark {
            // A lighter blue than the bars, so the thin fill does not turn navy.
            let tint = band == .tooCold ? Color(red: 0.45, green: 0.7, blue: 1.0) : color
            return AnyShapeStyle(tint.opacity(band == .ok ? 0.25 : band == .tooWarm ? 0.85 : 0.7))
        }
        let opacity = band == .ok ? 0.12 : 0.2
        guard band != .ok else { return AnyShapeStyle(color.opacity(opacity)) }
        return AnyShapeStyle(LinearGradient(
            colors: [color.opacity(opacity * 2), color.opacity(opacity * 0.4)],
            startPoint: band == .tooWarm ? .top : .bottom,
            endPoint: band == .tooWarm ? .bottom : .top
        ))
    }

    var body: some View {
        let selected = crosshair.flatMap { HeatingChartData.nearest(to: $0, in: samples) }
        let slots = slots
        let domain = HeatingChartData.timeDomain(samples)
        Chart {
            HeatingEventAreas(events: events, domain: domain)
            ForEach(HeatingChartData.gapSegments(samples)) { segment in
                ForEach(Array(segment.points.enumerated()), id: \.offset) { _, point in
                    AreaMark(x: .value("Zeit", point.date),
                             yStart: .value("Ist", point.ist),
                             yEnd: .value("Plan", point.plan),
                             series: .value("Abweichung", "gap-\(segment.id)"))
                        .foregroundStyle(gapStyle(segment.band))
                }
            }
            ForEach(Array(HeatingChartData.planRuns(samples).enumerated()), id: \.offset) { index, run in
                ForEach(Array(run.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("Zeit", point.date), y: .value("Plan", point.value), series: .value("Serie", "plan-\(index)"))
                        .interpolationMethod(.stepEnd)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(Color.secondary.opacity(0.55))
                }
            }
            ForEach(Array(HeatingChartData.istRuns(samples).enumerated()), id: \.offset) { index, run in
                ForEach(Array(run.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("Zeit", point.date), y: .value("Ist", point.value), series: .value("Serie", "ist-\(index)"))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(HeatingPalette.istLine(scheme: scheme))
                }
            }
            ForEach(slots.filter { $0.contains(selectedPinId) }.flatMap(\.events)) { event in
                RuleMark(x: .value("Zeit", event.pin))
                    .foregroundStyle(Color.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
            }
            if let selected {
                RuleMark(x: .value("Zeit", selected.date))
                    .foregroundStyle(Color.secondary.opacity(0.45))
                if let ist = selected.ist {
                    PointMark(x: .value("Zeit", selected.date), y: .value("Ist", ist))
                        .foregroundStyle(HeatingPalette.istLine(scheme: scheme))
                }
            }
        }
        .chartXScale(domain: HeatingChartData.timeDomain(samples))
        .chartYScale(domain: HeatingChartData.temperatureDomain(samples))
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(heatingGrid)
                AxisValueLabel {
                    if let degrees = value.as(Double.self) {
                        heatingYLabel("\(Int(degrees.rounded()))°")
                    }
                }
            }
        }
        .chartXAxis { HeatingTimeAxis.marks(range: range) }
        .chartPlotStyle { $0.clipped() }
        .chartOverlay { proxy in
            ZStack(alignment: .topLeading) {
                HeatingCrosshairOverlay(proxy: proxy, crosshair: $crosshair) { _, plotWidth in
                    if measuredWidth != plotWidth { measuredWidth = plotWidth }
                }
                pinRows(slots, proxy: proxy)
            }
        }
        .padding(.top, Self.pinAreaHeight)
    }

    /// The pins hang above the plot, outside the chart's clip: one button per slot, row 0 closest to the plot.
    private func pinRows(_ slots: [HeatingPinLayout.Slot], proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            if let frame = proxy.plotFrame {
                let plot = geometry[frame]
                ForEach(slots) { slot in
                    if let x = proxy.position(forX: slot.events[0].pin) {
                        Button { onSelectPin(slot.id) } label: {
                            HeatingPinBadge(slot: slot, isSelected: slot.contains(selectedPinId))
                                .frame(width: Self.pinWidth, height: Self.pinRowHeight)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: popoverBinding(for: slot), arrowEdge: .top) {
                            HeatingPinCard(events: slot.events, inPopover: true)
                                .frame(width: 260)
                        }
                        .position(x: plot.minX + min(max(x, Self.pinWidth / 2), plot.width - Self.pinWidth / 2),
                                  y: plot.minY - Self.pinRowHeight / 2 - 2 - CGFloat(slot.row) * Self.pinRowHeight)
                    }
                }
            }
        }
    }

    /// Regular layout: the popover belongs to the selected pin. Compact shows an inline card instead.
    private func popoverBinding(for slot: HeatingPinLayout.Slot) -> Binding<Bool> {
        Binding(get: { layout == .regular && slot.contains(selectedPinId) }, set: { if !$0 { onSelectPin(nil) } })
    }
}

/// The areas of events with a duration: window grey, fireplace soft orange.
struct HeatingEventAreas: ChartContent {
    let events: [HeatingEvent]
    let domain: ClosedRange<Date>

    var body: some ChartContent {
        ForEach(HeatingPinLayout.areas(events).filter { ($0.end ?? domain.upperBound) > domain.lowerBound && $0.start < domain.upperBound }) { event in
            RectangleMark(xStart: .value("Start", max(event.start, domain.lowerBound)), xEnd: .value("Ende", min(event.end ?? domain.upperBound, domain.upperBound)))
                .foregroundStyle(event.source == .fireplace ? Color.orange.opacity(0.1) : Color.gray.opacity(0.1))
        }
    }
}

/// Slim valve chart: one quiet line per radiator, only 0 and 100 % marked, names only on hover.
struct HeatingValveChart: View {
    let samples: [HeatingSample]
    var events: [HeatingEvent] = []
    let radiators: [String]
    @Binding var crosshair: Date?
    var range: HeatingRange = .day

    var body: some View {
        let selected = crosshair.flatMap { HeatingChartData.nearest(to: $0, in: samples) }
        Chart {
            HeatingEventAreas(events: events, domain: HeatingChartData.timeDomain(samples))
            ForEach(radiators.indices, id: \.self) { index in
                ForEach(Array(HeatingChartData.valveRuns(samples, radiator: index).enumerated()), id: \.offset) { run, points in
                    ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                        AreaMark(x: .value("Zeit", point.date), y: .value("Ventil", point.value), series: .value("Ventil", "\(index)-\(run)"))
                            .interpolationMethod(.stepEnd)
                            .foregroundStyle(HeatingPalette.valveFill(radiator: index))
                    }
                }
            }
            if let selected {
                RuleMark(x: .value("Zeit", selected.date))
                    .foregroundStyle(Color.secondary.opacity(0.45))
            }
        }
        .chartXScale(domain: HeatingChartData.timeDomain(samples))
        .chartYScale(domain: 0...100)
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 100]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(heatingGrid)
                AxisValueLabel { heatingYLabel("\(value.as(Int.self) ?? 0) %") }
            }
        }
        .chartXAxis(.hidden)
        .chartPlotStyle { $0.clipped() }
        .chartOverlay { proxy in
            HeatingCrosshairOverlay(proxy: proxy, crosshair: $crosshair)
        }
    }
}

enum HeatingTimeAxis {
    @AxisContentBuilder
    static func marks(range: HeatingRange) -> some AxisContent {
        let (component, count): (Calendar.Component, Int) = switch range {
        case .twoHours: (.minute, 30)
        case .day: (.hour, 6)
        case .week: (.day, 1)
        }
        AxisMarks(values: .stride(by: component, count: count)) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(heatingGrid)
            AxisValueLabel(centered: range == .week) {
                if let date = value.as(Date.self) {
                    Text(range == .week ? HeatingFormat.weekday(date) : HeatingFormat.time(date, includingDay: false))
                        .font(.caption2.monospacedDigit())
                }
            }
        }
    }
}

/// Hover (Mac, iPad pointer) or drag (touch) sets the crosshair; leaving or lifting clears it.
struct HeatingCrosshairOverlay: View {
    let proxy: ChartProxy
    @Binding var crosshair: Date?
    /// Reports the x (relative to the plot) and the width of the plot, so the pins can stack with the real width.
    var onPlot: (CGFloat, CGFloat) -> Void = { _, _ in }

    var body: some View {
        GeometryReader { geometry in
            let plot = proxy.plotFrame.map { geometry[$0] }
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onAppear { if let plot { onPlot(plot.minX, plot.width) } }
                .onChange(of: plot?.width) { if let plot { onPlot(plot.minX, plot.width) } }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location): crosshair = date(at: location, in: geometry)
                    case .ended: crosshair = nil
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { crosshair = date(at: $0.location, in: geometry) }
                        .onEnded { _ in crosshair = nil }
                )
        }
    }

    private func date(at location: CGPoint, in geometry: GeometryProxy) -> Date? {
        guard let plotFrame = proxy.plotFrame else { return nil }
        let x = location.x - geometry[plotFrame].origin.x
        return proxy.value(atX: x, as: Date.self)
    }
}

/// The range switch in neutral grey: a soft track and a lighter pill for the selection.
struct HeatingRangePicker: View {
    @Binding var range: HeatingRange

    private static let items: [(HeatingRange, String)] = [(.twoHours, "2 h"), (.day, "24 h"), (.week, "7 T")]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Self.items, id: \.0) { item, title in
                Button { range = item } label: {
                    Text(title)
                        .font(.subheadline.weight(range == item ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .frame(minWidth: 44, maxWidth: .infinity, minHeight: 28)
                        .background(range == item ? HeatingPalette.selectedSegment : .clear, in: .rect(cornerRadius: 7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(range == item ? .isSelected : [])
            }
        }
        .padding(2)
        .background(HeatingPalette.softFill, in: .rect(cornerRadius: 9))
        .frame(maxWidth: 190, alignment: .leading)
    }
}
