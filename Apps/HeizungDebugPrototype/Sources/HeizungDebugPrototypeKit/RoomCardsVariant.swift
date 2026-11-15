import SwiftUI

/// Variant B: the house now. One card per room with the current state and, per
/// radiator, the one-line answer to "warum kalt?". No chart; history is one tap away.
struct RoomCardsVariant: View {
    var body: some View {
        let radiators = MockData.radiators
        Screen(title: "Heizung", subtitle: "Stand \(Fmt.time(MockData.now))") {
            HStack(spacing: 8) {
                summaryPill("\(radiators.filter { $0.status == .warm }.count) heizen", .red)
                summaryPill("\(radiators.filter { $0.status == .cold }.count) kalt", .blue)
                summaryPill("\(radiators.filter { $0.status == .warning }.count) prüfen", .yellow)
                Spacer()
                Label("WP liefert (geschätzt)", systemImage: "heat.waves")
                    .font(.caption)
                    .foregroundStyle(.mint)
            }
            ForEach(MockData.rooms) { room in
                RoomCard(room: room)
            }
        }
    }

    private func summaryPill(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.15), in: .capsule)
            .foregroundStyle(color)
    }
}

struct RoomCard: View {
    let room: Room

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                Text(room.name).font(.title3.bold())
                Spacer()
                roomTemperature
            }
            HStack(spacing: 6) {
                Label("\(room.activePlan.label) \(Fmt.temp(room.activePlan.soll))", systemImage: "calendar")
                Text("→ \(room.nextPlan.time) \(Fmt.temp(room.nextPlan.soll))").foregroundStyle(.secondary)
            }
            .font(.caption)
            chips
            Divider()
            ForEach(room.radiators) { radiator in
                RadiatorRow(radiator: radiator)
            }
        }
    }

    @ViewBuilder
    private var roomTemperature: some View {
        if let sensor = room.sensor, sensor.failedSince == nil, let last = sensor.values.last {
            VStack(alignment: .trailing, spacing: 0) {
                Text(Fmt.temp(last.value)).font(.title2.monospacedDigit().weight(.semibold))
                if let since = sensor.values.steadySince(tolerance: 0.15) {
                    Text(Fmt.since(since)).font(.caption2).foregroundStyle(.secondary)
                }
            }
        } else {
            Label("Sensor aus", systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.yellow)
        }
    }

    @ViewBuilder
    private var chips: some View {
        let open = room.windows.filter(\.isOpen)
        if !open.isEmpty || room.isFireplaceOn || room.sensor?.failedSince != nil {
            HStack(spacing: 6) {
                ForEach(open) { window in
                    chip("\(window.name) offen", symbol: CauseKind.window.symbol, color: .orange)
                }
                if room.isFireplaceOn {
                    chip("Kamin an", symbol: CauseKind.fireplace.symbol, color: .brown)
                }
                if room.sensor?.failedSince != nil {
                    chip("Sensor ausgefallen", symbol: CauseKind.sensorFailure.symbol, color: .yellow)
                }
            }
        }
    }

    private func chip(_ text: String, symbol: String, color: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: .capsule)
            .foregroundStyle(color)
    }
}

struct RadiatorRow: View {
    let radiator: Radiator

    var body: some View {
        let cause = radiator.causes[0]
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                StatusDot(status: radiator.status)
                Text(radiator.name).font(.headline)
                Spacer()
                Text(radiator.status.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(radiator.status.color)
            }
            HStack(spacing: 14) {
                metric("Eve", Fmt.temp(radiator.currentEveIst))
                metric("Soll", radiator.isOff ? "Aus" : Fmt.temp(radiator.currentSoll))
                ValveGauge(percent: radiator.currentValve)
                if radiator.offset != 0 {
                    metric("Offset", Fmt.signed(radiator.offset))
                }
            }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: cause.kind.symbol)
                    .foregroundStyle(cause.kind.color)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(cause.title).font(.subheadline.weight(.semibold))
                    if let since = cause.since {
                        Text(Fmt.since(since)).font(.caption).foregroundStyle(.secondary)
                    }
                    if let until = cause.until {
                        Text(until).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cause.kind.color.opacity(0.08), in: .rect(cornerRadius: 8))
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout.monospacedDigit())
        }
    }
}

struct ValveGauge: View {
    let percent: Double

    var body: some View {
        Gauge(value: percent, in: 0...100) {
            Text("Ventil")
        } currentValueLabel: {
            Text("\(Int(percent))")
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(.cyan)
        .scaleEffect(0.6)
        .frame(width: 36, height: 36)
    }
}

#Preview("B Raumkarten") {
    RoomCardsVariant().environment(\.locale, Fmt.de)
}
