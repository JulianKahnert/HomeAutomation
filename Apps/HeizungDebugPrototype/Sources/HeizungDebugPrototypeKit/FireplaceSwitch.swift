import SwiftUI

/// Where the fireplace switch sits in G (candidates H-A…H-D). Mock only: the switch flips local
/// state, and the state acts on the fireplace rooms in overview and detail.
enum FireplacePlacement: Sendable {
    /// A: a row right under the headline, inside the overview card.
    case row
    /// B: a flame button at the trailing end of the headline.
    case headlineButton
    /// C: head of the detail card, only on rooms with a fireplace.
    case detailHeader
    /// D: toolbar button (drawn as a stand-in bar in the content, toolbars do not snapshot).
    case toolbar
}

extension EnvironmentValues {
    /// nil: the fireplace feature is off (variants A–G); otherwise the switch state.
    @Entry var fireplaceOn: Bool? = nil
}

enum FireplaceInfo {
    /// The automatic end the server writes ("automatisches Ende 03:30").
    static var endText: String {
        let end = Calendar.current.nextDate(after: FData.now, matching: DateComponents(hour: 3, minute: 30), matchingPolicy: .nextTime)!
        let hours = Int((end.timeIntervalSince(FData.now) / 3_600).rounded())
        return "endet in \(hours) h"
    }

    static func status(_ isOn: Bool) -> String { isOn ? "An · \(endText)" : "Aus" }
}

extension FRoom {
    var hasFireplace: Bool { events.contains { $0.kind == .fireplace } }

    /// Switched off: the still running fireplace interval disappears from pins and areas.
    func fireplace(_ isOn: Bool) -> FRoom {
        guard !isOn else { return self }
        return FRoom(
            id: id, placeId: placeId, name: name, short: short, radiators: radiators,
            istSource: istSource, samples: samples,
            events: events.filter { !($0.kind == .fireplace && ($0.end ?? .distantPast) >= FData.now) }
        )
    }
}

/// A and C: one quiet row, icon + state line + system switch.
struct GFireplaceRow: View {
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isOn ? "flame.fill" : "flame")
                .font(.title3)
                .foregroundStyle(isOn ? Color.orange : Color.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("Kamin").font(.subheadline.weight(.semibold))
                Text(FireplaceInfo.status(isOn)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Kamin", isOn: $isOn).labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(GStyle.soft, in: .rect(cornerRadius: 10))
    }
}

/// B: round flame button, the hint sits under it only while the fireplace runs.
struct GFireplaceButton: View {
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Button { isOn.toggle() } label: {
                Image(systemName: isOn ? "flame.fill" : "flame")
                    .font(.title3)
                    .foregroundStyle(isOn ? Color.orange : Color.secondary)
                    .frame(width: 40, height: 40)
                    .background(isOn ? Color.orange.opacity(0.18) : GStyle.soft, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Kamin")
            Text(isOn ? FireplaceInfo.endText : "Kamin aus")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// D: toolbar-style button in a stand-in navigation bar, state hint as a subtitle under the title.
struct GFireplaceToolbarButton: View {
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            Label("Kamin", systemImage: isOn ? "flame.fill" : "flame")
                .labelStyle(.iconOnly)
                .font(.body.weight(.medium))
                .foregroundStyle(isOn ? Color.orange : Color.primary)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: .circle)
                .overlay(Circle().strokeBorder(Color.secondary.opacity(0.15)))
        }
        .buttonStyle(.plain)
    }
}
