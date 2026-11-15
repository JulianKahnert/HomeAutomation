import SwiftUI

/// Variant D (hybrid): one radiator, the question first. The answer on top, then
/// a checklist of every possible cause in the priority order of the automation
/// (each ruled in or out), then a compact timeline, the "seit wann" facts and
/// the radiator's slice of the decision log.
struct DiagnosisVariant: View {
    @State var radiatorID: String

    private var radiator: Radiator { MockData.radiator(radiatorID) }
    private var room: Room { MockData.room(radiator.roomID) }

    var body: some View {
        Screen(title: radiator.name, subtitle: "\(room.name) · Offset \(Fmt.signed(radiator.offset))") {
            Picker("Heizkörper", selection: $radiatorID) {
                ForEach(MockData.radiators) { Text("\(MockData.room($0.roomID).name) · \($0.name)").tag($0.id) }
            }
            .pickerStyle(.menu)

            answer
            Card(title: "Geprüft, in der Reihenfolge der Automation") {
                ForEach(checks) { check in
                    CheckRow(check: check)
                }
            }
            Card(title: "Letzte 24 Stunden") {
                HeatingChart(radiator: radiator, room: room, height: 150, showsEvents: true)
                ValveChart(radiator: radiator, height: 50)
            }
            Card(title: "Seit wann") {
                SinceFacts(radiator: radiator, room: room)
            }
            Card(title: "Entscheidungen") {
                ForEach(MockData.log(for: radiator).prefix(5)) { entry in
                    LogRow(entry: entry, showsRoom: false)
                }
            }
        }
    }

    private var answer: some View {
        let cause = radiator.causes[0]
        return VStack(alignment: .leading, spacing: 8) {
            Text(radiator.status == .warm ? "Warum heizt er?" : "Warum ist \(radiator.name) kalt?")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: cause.kind.symbol)
                    .font(.title2)
                    .foregroundStyle(cause.kind.color)
                VStack(alignment: .leading, spacing: 4) {
                    Text(cause.title).font(.title3.bold())
                    if let since = cause.since {
                        Text(Fmt.since(since)).font(.callout.monospacedDigit())
                    }
                    Text(cause.detail).font(.callout).foregroundStyle(.secondary)
                    if let until = cause.until {
                        Label(until, systemImage: "arrow.forward.circle").font(.callout)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cause.kind.color.opacity(0.12), in: .rect(cornerRadius: 12))
    }

    // MARK: Checklist

    struct Check: Identifiable {
        enum Result { case yes, no, unknown }
        let kind: CauseKind
        let label: String
        let result: Result
        let detail: String
        var id: String { label }
    }

    private var checks: [Check] {
        let now = MockData.now
        let openWindow = room.windows.first(where: \.isOpen)
        let fireplace = radiator.isOnFireplaceList && room.isFireplaceOn
        let manual = radiator.causes.first { $0.kind == .manual }
        let setback = room.activePlan.soll < (room.plan.map(\.soll).max() ?? 0)
        let valveStuck = radiator.currentValve == 0 && !radiator.isOff && radiator.currentSoll > radiator.currentEveIst
        let heatPump = MockData.heatPumpDelivering.contains { $0.contains(now) }
        return [
            Check(kind: .modeOff, label: "Modus", result: radiator.isOff ? .yes : .no,
                  detail: radiator.isOff ? "Aus (Active = 0) \(Fmt.since(radiator.offIntervals.last!.start))" : "Heizen"),
            Check(kind: .window, label: "Fenster", result: openWindow == nil ? .no : .yes,
                  detail: openWindow.map { "\($0.name) offen \(Fmt.since($0.openIntervals.last!.start))" } ?? room.windows.map(\.name).joined(separator: ", ") + " zu"),
            Check(kind: .fireplace, label: "Kamin", result: fireplace ? .yes : .no,
                  detail: fireplace ? "an \(Fmt.since(room.fireplaceOn.last!.start))" : (radiator.isOnFireplaceList ? "aus" : (room.isFireplaceOn ? "an, aber Heizkörper nicht auf der Liste" : "nicht auf der Liste"))),
            Check(kind: .manual, label: "Manuell", result: manual == nil ? .no : .yes,
                  detail: manual.map { "\($0.title) um \(Fmt.time($0.since!))" } ?? "Soll entspricht dem letzten Schreibzugriff"),
            Check(kind: .planSetback, label: "Plan", result: setback ? .yes : .no,
                  detail: "\(room.activePlan.label) \(Fmt.temp(room.activePlan.soll)) + Offset \(Fmt.signed(radiator.offset)) seit \(room.activePlan.time)"),
            Check(kind: .valveClosed, label: "Ventil", result: valveStuck ? .yes : .no,
                  detail: "\(Fmt.percent(radiator.currentValve)) \(radiator.valve.steadySince().map { Fmt.since($0) } ?? "")"),
            Check(kind: .sensorFailure, label: "Raumsensor", result: room.sensor?.failedSince == nil ? .no : .yes,
                  detail: room.sensor.map { $0.failedSince.map { "ausgefallen \(Fmt.since($0))" } ?? "\($0.name) ok" } ?? "kein Sensor"),
            Check(kind: .heatPump, label: "Wärmepumpe", result: .unknown,
                  detail: heatPump ? "liefert vermutlich (geschätzt, v1 liest sie nicht)" : "IDA-Absenkung (geschätzt)"),
        ]
    }
}

struct CheckRow: View {
    let check: DiagnosisVariant.Check

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 18)
            Text(check.label)
                .font(.subheadline.weight(check.result == .yes ? .bold : .regular))
                .frame(width: 92, alignment: .leading)
            Text(check.detail)
                .font(.caption)
                .foregroundStyle(check.result == .yes ? .primary : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, check.result == .yes ? 6 : 0)
        .background(check.result == .yes ? check.kind.color.opacity(0.12) : .clear, in: .rect(cornerRadius: 6))
    }

    private var symbol: String {
        switch check.result {
        case .yes: "exclamationmark.circle.fill"
        case .no: "checkmark.circle"
        case .unknown: "questionmark.circle"
        }
    }

    private var color: Color {
        switch check.result {
        case .yes: check.kind.color
        case .no: .green
        case .unknown: .secondary
        }
    }
}

#Preview("D Diagnose – Bad OG, Ventil hängt") {
    DiagnosisVariant(radiatorID: "bad-1").environment(\.locale, Fmt.de)
}

#Preview("D Diagnose – Kaminzimmer Fenster, Kamin") {
    DiagnosisVariant(radiatorID: "kamin-fenster").environment(\.locale, Fmt.de)
}

#Preview("D Diagnose – Esszimmer, Sensor ausgefallen") {
    DiagnosisVariant(radiatorID: "ess-1").environment(\.locale, Fmt.de)
}

#Preview("D Diagnose – Schlafzimmer rechts, manuell") {
    DiagnosisVariant(radiatorID: "schlaf-rechts").environment(\.locale, Fmt.de)
}
