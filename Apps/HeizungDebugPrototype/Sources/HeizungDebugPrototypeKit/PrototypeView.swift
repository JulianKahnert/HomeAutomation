import SwiftUI

/// Entry point for the shell: one branch per variant, so menu, window title and
/// screenshots reach every candidate.
public struct PrototypeView: View {
    let variant: Variant

    public init(variant: Variant) {
        self.variant = variant
    }

    public var body: some View {
        Group {
            switch variant {
            case .timeline:
                TimelineVariant(radiatorID: "kueche-1")
            case .roomCards:
                RoomCardsVariant()
            case .decisionLog:
                DecisionLogVariant()
            case .diagnosis:
                DiagnosisVariant(radiatorID: "bad-1")
            case .skizzeV3:
                SkizzeV3Variant()
            case .final:
                // The live window decides the layout by width, like a size class would.
                GeometryReader { geo in
                    FinalVariant(layout: geo.size.width >= 700 ? .regular : .compact)
                }
            case .light:
                GeometryReader { geo in
                    // G_SCENARIO=hover|auswahl opens a fixed state for live checks.
                    LightScenarioView(
                        scenario: ProcessInfo.processInfo.environment["G_SCENARIO"] ?? "",
                        regular: geo.size.width >= 700
                    )
                }
            case .fireplaceRow:
                fireplace(.row)
            case .fireplaceButton:
                fireplace(.headlineButton)
            case .fireplaceDetail:
                fireplace(.detailHeader)
            case .fireplaceToolbar:
                fireplace(.toolbar)
            }
        }
        .environment(\.locale, Fmt.de)
    }
}

extension PrototypeView {
    /// G with the fireplace switch at one of the candidate places; Esszimmer preselected.
    func fireplace(_ placement: FireplacePlacement) -> some View {
        GeometryReader { geo in
            LightVariant(layout: geo.size.width >= 700 ? .regular : .compact, selectedRoomID: "esszimmer", range: .day, fireplace: placement)
        }
    }
}

// MARK: - Shared building blocks (styled after the Controller's inset-grouped lists)

struct Card<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title.uppercased())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: .rect(cornerRadius: 12))
        }
    }
}

struct Screen<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.largeTitle.bold())
                    if let subtitle {
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                content
            }
            .padding(16)
        }
        .frame(width: 430)
        // Controller look: grouped background, white cards; fixed light so snapshots compare.
        .background(Color(white: 0.95))
        .environment(\.colorScheme, .light)
    }
}

struct CauseBadge: View {
    let kind: CauseKind

    var body: some View {
        Label(kind.label, systemImage: kind.symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(kind.color)
            .background(kind.color.opacity(0.15), in: .capsule)
    }
}

struct StatusDot: View {
    let status: RadiatorStatus

    var body: some View {
        Image(systemName: status == .warning ? "exclamationmark.triangle.fill" : "heater.vertical.fill")
            .foregroundStyle(status.color)
    }
}

/// "Raum 20,6 °C seit 21:10" – answers "seit wann bei Z?" from the series itself.
struct SinceRow: View {
    let label: String
    let value: String
    let since: Date?
    var color: Color = .primary

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.body.monospacedDigit().weight(.semibold)).foregroundStyle(color)
            if let since {
                Text(Fmt.since(since))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 150, alignment: .trailing)
            } else {
                Text("–").font(.caption).foregroundStyle(.secondary).frame(width: 150, alignment: .trailing)
            }
        }
    }
}

struct SinceFacts: View {
    let radiator: Radiator
    let room: Room

    var body: some View {
        VStack(spacing: 8) {
            SinceRow(label: "Eve-Ist", value: Fmt.temp(radiator.currentEveIst), since: radiator.eveIst.steadySince(), color: .red)
            if let sensor = room.sensor, sensor.failedSince == nil {
                SinceRow(label: "Raum-Ist", value: Fmt.temp(sensor.values.last?.value ?? .nan), since: sensor.values.steadySince(tolerance: 0.15), color: .purple)
            } else {
                SinceRow(label: "Raum-Ist", value: "ausgefallen", since: room.sensor?.failedSince, color: .yellow)
            }
            SinceRow(label: radiator.isOff ? "Modus" : "Soll", value: radiator.isOff ? "Aus" : Fmt.temp(radiator.currentSoll), since: radiator.isOff ? radiator.offIntervals.last?.start : radiator.soll.steadySince(), color: .orange)
            SinceRow(label: "Ventil", value: Fmt.percent(radiator.currentValve), since: radiator.valve.steadySince(), color: .cyan)
        }
    }
}

#Preview("Bausteine") {
    VStack(alignment: .leading) {
        CauseBadge(kind: .window)
        CauseBadge(kind: .valveClosed)
        SinceFacts(radiator: MockData.radiator("bad-1"), room: MockData.room("bad-og"))
    }
    .padding()
    .frame(width: 430)
}
