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
    /// The selected moment of the crosshair; driven by hover or drag, preset in previews.
    @State var crosshair: Date?
    var onClose: (() -> Void)?

    @Environment(\.colorScheme) private var scheme

    private var shown: HeatingSample? {
        crosshair.flatMap { HeatingChartData.nearest(to: $0, in: detail.samples) } ?? detail.latest
    }

    private var includesDay: Bool { range == .week }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HeatingCard {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    Picker("Zeitraum", selection: $range) {
                        Text("2 h").tag(HeatingRange.twoHours)
                        Text("24 h").tag(HeatingRange.day)
                        Text("7 T").tag(HeatingRange.week)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    HeatingSollIstChart(samples: detail.samples, crosshair: $crosshair, includesDay: includesDay)
                        .frame(height: 220)
                        .overlay {
                            if detail.hasNoData {
                                Text("Keine Daten im Zeitraum")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    Text(sourceText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !detail.radiators.isEmpty {
                HeatingCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ventile")
                            .font(.headline)
                        HeatingValveChart(samples: detail.samples, radiators: detail.radiators, crosshair: $crosshair)
                            .frame(height: 80)
                        valveCaption
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(detail.name)
                    .font(.headline)
                if let sample = shown, let ist = sample.ist {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(HeatingFormat.degrees(ist))
                            .font(.largeTitle.weight(.semibold).monospacedDigit())
                        if let plan = sample.sollPlan {
                            Text("Plan \(HeatingFormat.degrees(plan))")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        if let delta = sample.delta {
                            Text(HeatingFormat.kelvin(delta))
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(HeatingPalette.color(forDelta: delta, scheme: scheme))
                        }
                    }
                    if crosshair != nil {
                        Text(HeatingFormat.time(sample.date, includingDay: includesDay))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Kein Ist-Wert")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let onClose {
                Button("Schließen", systemImage: "xmark.circle.fill", action: onClose)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.title2)
            }
        }
    }

    private var sourceText: String {
        switch detail.istSource {
        case .roomSensor(let name): "Ist vom Raumsensor \(name)"
        case .thermostats: "Ist: Mittel der Thermostate"
        }
    }

    @ViewBuilder
    private var valveCaption: some View {
        if let sample = shown {
            let parts = detail.radiators.enumerated().map { index, name -> String in
                let value = sample.valves.indices.contains(index) ? sample.valves[index] : nil
                return "\(name) \(value.map(HeatingFormat.percent) ?? "–")"
            }
            Text(parts.joined(separator: " · "))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

/// Soft grey actual line, dashed plan line, colour only in the gap between them.
struct HeatingSollIstChart: View {
    let samples: [HeatingSample]
    @Binding var crosshair: Date?
    var includesDay = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let selected = crosshair.flatMap { HeatingChartData.nearest(to: $0, in: samples) }
        Chart {
            ForEach(HeatingChartData.gapSegments(samples)) { segment in
                ForEach(Array(segment.points.enumerated()), id: \.offset) { _, point in
                    AreaMark(x: .value("Zeit", point.date),
                             yStart: .value("Ist", point.ist),
                             yEnd: .value("Plan", point.plan),
                             series: .value("Abweichung", segment.id))
                        .foregroundStyle(HeatingPalette.color(segment.band, scheme: scheme).opacity(scheme == .dark ? 0.5 : 0.3))
                }
            }
            ForEach(Array(HeatingChartData.planRuns(samples).enumerated()), id: \.offset) { index, run in
                ForEach(Array(run.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("Zeit", point.date), y: .value("Plan", point.value), series: .value("Planlinie", index))
                        .interpolationMethod(.stepEnd)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .foregroundStyle(HeatingPalette.istLine(scheme: scheme).opacity(0.55))
                }
            }
            ForEach(Array(HeatingChartData.istRuns(samples).enumerated()), id: \.offset) { index, run in
                ForEach(Array(run.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("Zeit", point.date), y: .value("Ist", point.value), series: .value("Istlinie", index))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(HeatingPalette.istLine(scheme: scheme))
                }
            }
            if let selected {
                RuleMark(x: .value("Zeit", selected.date))
                    .foregroundStyle(.gray.opacity(0.5))
                if let ist = selected.ist {
                    PointMark(x: .value("Zeit", selected.date), y: .value("Ist", ist))
                        .foregroundStyle(HeatingPalette.istLine(scheme: scheme))
                }
            }
        }
        .chartYScale(domain: HeatingChartData.temperatureDomain(samples))
        .chartYAxis(.hidden)
        .chartXAxis { HeatingTimeAxis.marks(includesDay: includesDay) }
        .chartPlotStyle { $0.clipped() }
        .chartOverlay { proxy in
            HeatingCrosshairOverlay(proxy: proxy, crosshair: $crosshair)
        }
    }
}

/// Slim valve chart: one stepped area per radiator, only 0 and 100 % on the axis.
struct HeatingValveChart: View {
    let samples: [HeatingSample]
    let radiators: [String]
    @Binding var crosshair: Date?

    var body: some View {
        let selected = crosshair.flatMap { HeatingChartData.nearest(to: $0, in: samples) }
        Chart {
            ForEach(radiators.indices, id: \.self) { index in
                ForEach(Array(HeatingChartData.valveRuns(samples, radiator: index).enumerated()), id: \.offset) { run, points in
                    ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                        AreaMark(x: .value("Zeit", point.date), y: .value("Ventil", point.value), series: .value("Ventil", "\(index)-\(run)"))
                            .interpolationMethod(.stepEnd)
                            .foregroundStyle(HeatingPalette.valveColors[index % HeatingPalette.valveColors.count].opacity(0.35))
                    }
                }
            }
            if let selected {
                RuleMark(x: .value("Zeit", selected.date))
                    .foregroundStyle(.gray.opacity(0.5))
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 100]) { value in
                AxisValueLabel { Text("\(value.as(Int.self) ?? 0) %").font(.caption2) }
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
    static func marks(includesDay: Bool) -> some AxisContent {
        AxisMarks(preset: .aligned, values: .automatic(desiredCount: 4)) { value in
            AxisValueLabel {
                if let date = value.as(Date.self) {
                    Text(HeatingFormat.time(date, includingDay: includesDay))
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

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
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
