import Charts
import SwiftUI

/// Variant A: everything on one time axis. Ist/Soll/Außen overlaid, valve below,
/// state lanes under that, server writes as markers. The user reads the "why"
/// off the picture.
struct TimelineVariant: View {
    @State var radiatorID: String

    private var radiator: Radiator { MockData.radiator(radiatorID) }
    private var room: Room { MockData.room(radiator.roomID) }

    var body: some View {
        Screen(title: "Verlauf", subtitle: "Letzte 24 Stunden · bis \(Fmt.time(MockData.now))") {
            Picker("Heizkörper", selection: $radiatorID) {
                ForEach(MockData.rooms) { room in
                    Section(room.name) {
                        ForEach(room.radiators) { Text("\(room.name) · \($0.name)").tag($0.id) }
                    }
                }
            }
            .pickerStyle(.menu)

            Card(title: "Temperatur") {
                HeatingChart(radiator: radiator, room: room, height: 220)
                ChartLegend()
            }
            Card(title: "Ventil") {
                ValveChart(radiator: radiator, height: 80)
            }
            Card(title: "Zustände") {
                StateLanes(radiator: radiator, room: room)
            }
            Card(title: "Seit wann") {
                SinceFacts(radiator: radiator, room: room)
            }
        }
    }
}

// MARK: - Charts shared by A and D

struct HeatingChart: View {
    let radiator: Radiator
    let room: Room
    var height: CGFloat = 220
    var showsEvents = true

    var body: some View {
        Chart {
            ForEach(radiator.offIntervals, id: \.start) { interval in
                RectangleMark(xStart: .value("Start", interval.start), xEnd: .value("Ende", interval.end))
                    .foregroundStyle(Color.gray.opacity(0.18))
            }
            ForEach(room.windows.flatMap(\.openIntervals), id: \.start) { interval in
                RectangleMark(xStart: .value("Start", interval.start), xEnd: .value("Ende", interval.end))
                    .foregroundStyle(Color.orange.opacity(0.25))
            }
            ForEach(room.fireplaceOn, id: \.start) { interval in
                RectangleMark(xStart: .value("Start", interval.start), xEnd: .value("Ende", interval.end))
                    .foregroundStyle(Color.brown.opacity(0.15))
            }
            series("Soll", radiator.soll, interpolation: .stepEnd)
            series("Eve-Ist", radiator.eveIst, interpolation: .stepEnd)
            if let sensor = room.sensor {
                series("Raum-Ist", sensor.values, interpolation: .linear)
            }
            series("Außen", MockData.outside, interpolation: .linear)
            if showsEvents {
                ForEach(MockData.log(for: radiator).filter { $0.kind != .observation || $0.radiatorID == radiator.id }) { entry in
                    RuleMark(x: .value("Zeit", entry.date))
                        .foregroundStyle(entry.causeKind.color.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        .annotation(position: .top, spacing: 2) {
                            Image(systemName: entry.causeKind.symbol)
                                .font(.system(size: 9))
                                .foregroundStyle(entry.causeKind.color)
                        }
                }
            }
        }
        .chartForegroundStyleScale(["Soll": Color.orange, "Eve-Ist": Color.red, "Raum-Ist": Color.purple, "Außen": Color.gray])
        .chartLegend(.hidden)
        .chartXScale(domain: MockData.domain)
        .chartYScale(domain: -2...26)
        .chartYAxis { AxisMarks(values: [0, 5, 10, 15, 20, 25]) { AxisGridLine(); AxisValueLabel() } }
        .chartXAxis {
            AxisMarks(preset: .aligned, values: .stride(by: .hour, count: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
            }
        }
        .frame(height: height)
    }

    @ChartContentBuilder
    private func series(_ name: String, _ samples: [Sample], interpolation: InterpolationMethod) -> some ChartContent {
        ForEach(samples, id: \.date) { sample in
            LineMark(x: .value("Zeit", sample.date), y: .value("°C", sample.value), series: .value("Serie", name))
                .foregroundStyle(by: .value("Serie", name))
                .interpolationMethod(interpolation)
                .lineStyle(StrokeStyle(lineWidth: name == "Außen" ? 1 : 2, dash: name == "Außen" ? [3, 3] : (name == "Soll" ? [6, 2] : [])))
        }
    }
}

struct ChartLegend: View {
    var body: some View {
        let items: [(String, Color)] = [("Soll", .orange), ("Eve-Ist", .red), ("Raum-Ist", .purple), ("Außen", .gray)]
        let bands: [(String, Color)] = [("Fenster offen", .orange.opacity(0.35)), ("Kamin", .brown.opacity(0.3)), ("Modus Aus", .gray.opacity(0.3))]
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                ForEach(items, id: \.0) { item in
                    HStack(spacing: 4) {
                        Capsule().fill(item.1).frame(width: 14, height: 3)
                        Text(item.0)
                    }
                }
            }
            HStack(spacing: 12) {
                ForEach(bands, id: \.0) { item in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(item.1).frame(width: 12, height: 10)
                        Text(item.0)
                    }
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

struct ValveChart: View {
    let radiator: Radiator
    var height: CGFloat = 80

    var body: some View {
        Chart(radiator.valve, id: \.date) { sample in
            AreaMark(x: .value("Zeit", sample.date), y: .value("%", sample.value))
                .interpolationMethod(.stepEnd)
                .foregroundStyle(Color.cyan.opacity(0.35))
            LineMark(x: .value("Zeit", sample.date), y: .value("%", sample.value))
                .interpolationMethod(.stepEnd)
                .foregroundStyle(Color.cyan)
        }
        .chartXScale(domain: MockData.domain)
        .chartYScale(domain: 0...100)
        .chartYAxis { AxisMarks(values: [0, 50, 100]) { value in AxisGridLine(); AxisValueLabel("\(value.as(Int.self) ?? 0) %") } }
        .chartXAxis {
            AxisMarks(preset: .aligned, values: .stride(by: .hour, count: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
            }
        }
        .frame(height: height)
    }
}

/// Lanes in the style of the Controller's TimelineChart.
struct StateLanes: View {
    let radiator: Radiator
    let room: Room

    private struct Lane: Identifiable {
        let label: String
        let color: Color
        let intervals: [DateInterval]
        var id: String { label }
    }

    private var lanes: [Lane] {
        var lanes = [
            Lane(label: "Fenster", color: .orange, intervals: room.windows.flatMap(\.openIntervals)),
            Lane(label: "Kamin", color: .brown, intervals: radiator.isOnFireplaceList ? room.fireplaceOn : []),
            Lane(label: "Modus Aus", color: .gray, intervals: radiator.offIntervals),
            Lane(label: "Sensor aus", color: .yellow, intervals: room.sensor?.failedSince.map { [DateInterval(start: $0, end: MockData.now)] } ?? []),
            Lane(label: "WP (geschätzt)", color: .mint, intervals: MockData.heatPumpDelivering),
        ]
        if !radiator.isOnFireplaceList && !room.fireplaceOn.isEmpty {
            lanes[1] = Lane(label: "Kamin (n. a. Liste)", color: .brown.opacity(0.4), intervals: room.fireplaceOn)
        }
        return lanes
    }

    var body: some View {
        // Numeric rows: categorical y labels drift half a band off their bars.
        let rows = lanes.count
        Chart {
            ForEach(Array(lanes.enumerated()), id: \.element.id) { index, lane in
                ForEach(lane.intervals, id: \.start) { interval in
                    RectangleMark(
                        xStart: .value("Start", interval.start),
                        xEnd: .value("Ende", max(interval.end, interval.start.addingTimeInterval(300))),
                        yStart: .value("Spur", Double(rows - index) - 0.75),
                        yEnd: .value("Spur", Double(rows - index) - 0.25)
                    )
                    .foregroundStyle(lane.color)
                    .clipShape(.rect(cornerRadius: 3))
                }
            }
        }
        .chartXScale(domain: MockData.domain)
        .chartYScale(domain: 0...Double(rows))
        .chartYAxis {
            AxisMarks(position: .leading, values: lanes.indices.map { Double(rows - $0) - 0.5 }) { value in
                let index = rows - Int((value.as(Double.self) ?? 0) + 0.5)
                AxisValueLabel(lanes[index].label)
            }
        }
        .chartXAxis {
            AxisMarks(preset: .aligned, values: .stride(by: .hour, count: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
            }
        }
        .frame(height: CGFloat(lanes.count) * 26 + 30)
    }
}

#Preview("A Zeitleiste – Küche, Fenster offen") {
    TimelineVariant(radiatorID: "kueche-1").environment(\.locale, Fmt.de)
}

#Preview("A Zeitleiste – Bad OG, Ventil hängt") {
    TimelineVariant(radiatorID: "bad-1").environment(\.locale, Fmt.de)
}

#Preview("A Zeitleiste – Arbeitszimmer, Offset") {
    TimelineVariant(radiatorID: "arbeit-1").environment(\.locale, Fmt.de)
}
