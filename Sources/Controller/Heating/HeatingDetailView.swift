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
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(HeatingPalette.card))
    }
}

/// One part of the Heizung tab as a section: the headline above the card, a note below it.
struct HeatingSection<Content: View, Header: View, Footer: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var header: Header
    @ViewBuilder var footer: Footer

    var body: some View {
        // A plain stack instead of a List: the cards, their charts and their gestures stay as they are.
        VStack(alignment: .leading, spacing: 6) {
            Section {
                HeatingCard { content }
            } header: {
                header
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 4)
            } footer: {
                footer
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
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
    /// The selected moment of the crosshair; driven by hover or drag, preset in previews.
    @State var crosshair: Date?
    var onClose: (() -> Void)?

    @Environment(\.colorScheme) private var scheme
    /// The plot width the chart measured: its pins and the inline card group with the same width.
    @State private var measuredPlotWidth: CGFloat?

    private var plotWidth: CGFloat { measuredPlotWidth ?? layout.plotWidthEstimate }

    private var shown: HeatingSample? {
        crosshair.flatMap { HeatingChartData.nearest(to: $0, in: detail.samples) } ?? detail.latest
    }

    private var includesDay: Bool { range == .week }

    var body: some View {
        // Laid out once per render: the chart draws them, the inline card shows the selected one.
        let slots = HeatingSollIstChart.slots(events: detail.events, samples: detail.samples, range: range, plotWidth: plotWidth)
        let selectedSlot = slots.first { $0.contains(selectedPinId) }
        HeatingSection {
            VStack(alignment: .leading, spacing: 8) {
                readout
                HeatingRangePicker(range: $range)
                    .padding(.bottom, 8)
                HeatingSollIstChart(samples: detail.samples, events: detail.events, crosshair: $crosshair, range: range,
                                    selectedPinId: selectedPinId, onSelectPin: onSelectPin, layout: layout, slots: slots,
                                    onPlotWidth: { measuredPlotWidth = $0 })
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
        } header: {
            HStack(alignment: .firstTextBaseline) {
                Text(detail.name)
                Spacer()
                if let onClose {
                    Button("Schließen", systemImage: "xmark.circle.fill", action: onClose)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(.tertiary)
                        .font(.title3)
                }
            }
        } footer: {
            // Where the actual value comes from does not change with the crosshair, so it sits below the card.
            VStack(alignment: .leading, spacing: 2) {
                Label(sourceText, systemImage: sourceSymbol)
                if detail.latest?.ist == nil {
                    Text(lastIstText)
                }
                if let offHint {
                    Text(offHint)
                }
            }
        }
    }

    /// The values at the crosshair, else the latest. Every line keeps its height while the crosshair comes and
    /// goes: the variants are stacked and only swapped by opacity, so a long press on the chart moves nothing.
    private var readout: some View {
        VStack(alignment: .leading, spacing: 2) {
            ZStack(alignment: .leading) {
                Text("Jetzt")
                    .opacity(crosshair == nil ? 1 : 0)
                Text(shown.map { HeatingFormat.time($0.date, includingDay: includesDay) } ?? "")
                    .opacity(crosshair == nil ? 0 : 1)
            }
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            ZStack(alignment: .leading) {
                // Holds the height of the large value, also while "Kein Ist-Wert" is shown.
                Text("0").font(.largeTitle.weight(.semibold)).hidden()
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let ist = shown?.ist {
                        Text(HeatingFormat.degrees(ist))
                            .font(.largeTitle.weight(.semibold).monospacedDigit())
                    } else {
                        Text("Kein Ist-Wert")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    if let period = shownOffPeriod {
                        // The plan did not apply: the cause instead of plan and Δ, in one line of the same font.
                        Label("Heizung aus · \(period.source.label)", systemImage: period.source.offSymbol)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(period.source == .fireplace ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                            .lineLimit(1)
                    } else {
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
                }
            }
        }
    }

    private var offPeriods: [HeatingChartData.OffPeriod] {
        HeatingChartData.offPeriods(detail.events, in: HeatingChartData.timeDomain(detail.samples))
    }

    /// The window or fireplace stretch of the shown moment, when the radiators were off then.
    private var shownOffPeriod: HeatingChartData.OffPeriod? {
        shown.flatMap { HeatingChartData.offPeriod(at: $0.date, in: offPeriods) }
    }

    /// Explains the bands of the charts, naming only the causes the range has.
    private var offHint: String? {
        let sources = Set(offPeriods.map(\.source))
        var parts: [String] = []
        if sources.contains(.window) { parts.append("grau: Fenster offen") }
        if sources.contains(.fireplace) { parts.append("orange: Kamin an") }
        guard !parts.isEmpty else { return nil }
        return "Flächen: Heizung aus, \(parts.joined(separator: ", "))."
    }

    private var lastIstText: String {
        guard let last = detail.lastIst else { return "bisher kein Ist-Wert" }
        return "kein Ist-Wert seit \(HeatingFormat.time(last, includingDay: true))"
    }

    private var sourceSymbol: String {
        switch detail.istSource {
        case .roomSensor: return "thermometer.medium"
        case .thermostats: return "heater.vertical"
        }
    }

    private var sourceText: String {
        switch detail.istSource {
        case .roomSensor(let name): return "Raumsensor „\(name)“"
        case .thermostats: return "Mittel der Thermostate"
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
        // One line also with many or long radiator names, so the valve chart does not move.
        .lineLimit(1)
    }
}

/// Trailing labels of one width in both charts, so the plots and the crosshair line up. The width is the
/// widest label's own, measured with an invisible template, so it follows the text size.
private func heatingYLabel(_ text: String) -> some View {
    ZStack(alignment: .leading) {
        Text("100 %").hidden()
        Text(text)
    }
    .font(.caption2.monospacedDigit())
    .lineLimit(1)
    .fixedSize()
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
    /// The pins, laid out by the caller with the plot width the chart reports through `onPlotWidth`.
    var slots: [HeatingPinLayout.Slot] = []
    var onPlotWidth: (CGFloat) -> Void = { _ in }

    static let pinWidth: CGFloat = 22
    static let pinRowHeight: CGFloat = 22
    static let pinRows = 2
    /// Room above the plot for the pin rows.
    static let pinAreaHeight: CGFloat = pinRowHeight * CGFloat(pinRows) + 4

    static func slots(events: [HeatingEvent], samples: [HeatingSample], range: HeatingRange, plotWidth: CGFloat) -> [HeatingPinLayout.Slot] {
        HeatingPinLayout.slots(HeatingPinLayout.pins(events, range: range), in: HeatingChartData.timeDomain(samples), plotWidth: plotWidth, pinWidth: pinWidth, rows: pinRows)
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
        let domain = HeatingChartData.timeDomain(samples)
        let off = HeatingChartData.offPeriods(events, in: domain)
        Chart {
            HeatingOffAreas(periods: off, scheme: scheme, showsSymbols: true)
            ForEach(HeatingChartData.gapSegments(samples, off: off)) { segment in
                ForEach(Array(segment.points.enumerated()), id: \.offset) { _, point in
                    AreaMark(x: .value("Zeit", point.date),
                             yStart: .value("Ist", point.ist),
                             yEnd: .value("Plan", point.plan),
                             series: .value("Abweichung", "gap-\(segment.id)"))
                        .foregroundStyle(gapStyle(segment.band))
                }
            }
            ForEach(Array(HeatingChartData.planRuns(samples, off: off).enumerated()), id: \.offset) { index, run in
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
        .chartXScale(domain: domain)
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
        // Swift Charts' own selection: drag or hover moves the crosshair, a vertical swipe still scrolls the page.
        .chartXSelection(value: $crosshair)
        .chartOverlay { proxy in
            ZStack(alignment: .topLeading) {
                HeatingPlotWidthReader(proxy: proxy, onPlotWidth: onPlotWidth)
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
                        pinButton(slot)
                            .position(Self.pinCenter(x: x, row: slot.row, in: plot))
                    }
                }
            }
        }
    }

    private func pinButton(_ slot: HeatingPinLayout.Slot) -> some View {
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
    }

    /// Clamped so a pin at the edge stays fully inside the plot; each row sits one pin height higher.
    private static func pinCenter(x: CGFloat, row: Int, in plot: CGRect) -> CGPoint {
        let halfWidth: CGFloat = pinWidth / 2
        let clampedX: CGFloat = min(max(x, halfWidth), plot.width - halfWidth)
        let rowOffset: CGFloat = CGFloat(row) * pinRowHeight
        return CGPoint(x: plot.minX + clampedX, y: plot.minY - pinRowHeight / 2 - 2 - rowOffset)
    }

    /// Regular layout: the popover belongs to the selected pin. Compact shows an inline card instead.
    private func popoverBinding(for slot: HeatingPinLayout.Slot) -> Binding<Bool> {
        Binding(get: { layout == .regular && slot.contains(selectedPinId) }, set: { if !$0 { onSelectPin(nil) } })
    }
}

/// The stretches in which a window (grey) or the fireplace (orange) switched the radiators off: a band over the
/// full height, in the temperature chart with the cause's symbol at its top.
struct HeatingOffAreas: ChartContent {
    let periods: [HeatingChartData.OffPeriod]
    let scheme: ColorScheme
    var showsSymbols = false

    var body: some ChartContent {
        ForEach(periods) { period in
            RectangleMark(xStart: .value("Start", period.range.lowerBound), xEnd: .value("Ende", period.range.upperBound))
                .foregroundStyle(HeatingPalette.offFill(period.source, scheme: scheme))
                .annotation(position: .overlay, alignment: .top, spacing: 4) {
                    if showsSymbols {
                        Image(systemName: period.source.offSymbol)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(period.source == .fireplace ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                            .accessibilityLabel("\(period.source.label): Heizung aus")
                    }
                }
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

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let selected = crosshair.flatMap { HeatingChartData.nearest(to: $0, in: samples) }
        let domain = HeatingChartData.timeDomain(samples)
        Chart {
            HeatingOffAreas(periods: HeatingChartData.offPeriods(events, in: domain), scheme: scheme)
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
        .chartXScale(domain: domain)
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
        .chartXSelection(value: $crosshair)
    }
}

enum HeatingTimeAxis {
    private static func stride(for range: HeatingRange) -> (component: Calendar.Component, count: Int) {
        switch range {
        case .twoHours: return (.minute, 30)
        case .day: return (.hour, 6)
        case .week: return (.day, 1)
        }
    }

    @AxisContentBuilder
    static func marks(range: HeatingRange) -> some AxisContent {
        let step = stride(for: range)
        AxisMarks(values: .stride(by: step.component, count: step.count)) { value in
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

/// Reports the width of the plot, so the pins can stack with the real width. Takes no touches: the selection
/// belongs to the chart.
struct HeatingPlotWidthReader: View {
    let proxy: ChartProxy
    var onPlotWidth: (CGFloat) -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = proxy.plotFrame.map { geometry[$0].width }
            Color.clear
                .onAppear { if let width { onPlotWidth(width) } }
                .onChange(of: width) { if let width { onPlotWidth(width) } }
        }
        .allowsHitTesting(false)
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

// MARK: - Previews

private extension HeatingRoomDetail {
    static var preview: HeatingRoomDetail {
        guard let detail = HeatingPreviewData.state("Bad OG").detail else { fatalError("The preview data has the room Bad OG") }
        return detail
    }
}

#Preview("Card") {
    HeatingCard { Text("Inhalt der Karte") }.padding(16)
}

#Preview("Raumdetail") {
    @Previewable @State var range = HeatingRange.day
    HeatingRoomDetailView(detail: .preview, range: $range, selectedPinId: nil)
        .padding(16)
        .frame(width: 402)
}

#Preview("Soll-Ist-Diagramm") {
    @Previewable @State var crosshair: Date?
    let detail = HeatingRoomDetail.preview
    HeatingSollIstChart(samples: detail.samples, events: detail.events, crosshair: $crosshair)
        .frame(width: 402, height: 260)
        .padding(16)
}

#Preview("Ventil-Diagramm") {
    @Previewable @State var crosshair: Date?
    let detail = HeatingRoomDetail.preview
    HeatingValveChart(samples: detail.samples, events: detail.events, radiators: detail.radiators, crosshair: $crosshair)
        .frame(width: 402, height: 120)
        .padding(16)
}

#Preview("Fadenkreuz") {
    @Previewable @State var crosshair: Date?
    let detail = HeatingRoomDetail.preview
    Chart(detail.samples, id: \.date) { sample in
        LineMark(x: .value("Zeit", sample.date), y: .value("Ist", sample.ist ?? 0))
    }
    .chartXSelection(value: $crosshair)
    .frame(width: 402, height: 160)
    .padding(16)
}

#Preview("Zeitraum") {
    @Previewable @State var range = HeatingRange.day
    HeatingRangePicker(range: $range).padding(16)
}
