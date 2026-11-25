//
//  HeatingPinViews.swift
//  ControllerFeatures
//
//  Event pins as SF Symbols and the card with the reason (popover on Mac/iPad, inline on iPhone)
//

import HAModels
import SwiftUI

extension HeatingEventSource {
    var symbol: String {
        switch self {
        case .plan: return "calendar"
        case .window: return "window.vertical.open"
        case .fireplace: return "flame"
        case .observed: return "hand.raised"
        case .system: return "gearshape"
        }
    }

    /// The symbol at the top of an off band: filled, so it reads on the tinted band.
    var offSymbol: String {
        self == .fireplace ? "flame.fill" : symbol
    }

    var label: String {
        switch self {
        case .plan: return "Plan"
        case .window: return "Fenster"
        case .fireplace: return "Kamin"
        case .observed: return "Von Hand"
        case .system: return "System"
        }
    }
}

/// A quiet pin: the symbol alone in secondary, primary on a soft capsule while selected; "+n" for a group.
struct HeatingPinBadge: View {
    let slot: HeatingPinLayout.Slot
    var isSelected = false

    var body: some View {
        Group {
            if let badge = slot.badge {
                Text(badge).font(.caption2.weight(.semibold)).monospacedDigit()
            } else {
                Image(systemName: slot.events[0].source.symbol).font(.caption)
            }
        }
        .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .frame(minWidth: 18, minHeight: 18)
        .background(isSelected ? HeatingPalette.softFill : .clear, in: .capsule)
        .accessibilityLabel(slot.badge.map { "\($0) Ereignisse" } ?? slot.events[0].source.label)
    }
}

/// The reason of one pin or the list of a "+n" pin.
struct HeatingPinCard: View {
    let events: [HeatingEvent]
    var inPopover = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(events) { event in
                VStack(alignment: .leading, spacing: 2) {
                    Label {
                        Text(header(event)).monospacedDigit()
                    } icon: {
                        Image(systemName: event.source.symbol)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Text(event.title).font(.subheadline.weight(.medium))
                    Text(event.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(inPopover ? AnyShapeStyle(.clear) : AnyShapeStyle(HeatingPalette.softFill), in: .rect(cornerRadius: 12))
    }

    private func header(_ event: HeatingEvent) -> String {
        var text = "\(event.source.label) · \(HeatingFormat.time(event.start, includingDay: true))"
        if let end = event.end { text += " – \(HeatingFormat.time(end, includingDay: false))" } else if event.hasDuration { text += " – jetzt" }
        return text
    }
}

// MARK: - Previews

#Preview("Pins") {
    HStack(spacing: 12) {
        ForEach(HeatingEventSource.allCases, id: \.self) { source in
            HeatingPinBadge(slot: .init(x: 0, row: 0, events: [HeatingEvent(source: source, title: source.label, reason: "", start: HeatingPreviewData.now)]))
        }
        HeatingPinBadge(slot: .init(x: 0, row: 0, events: HeatingPreviewData.kitchenEvents), isSelected: true)
    }
    .padding(16)
}

#Preview("Pin-Karte") {
    HeatingPinCard(events: Array(HeatingPreviewData.kitchenEvents.prefix(2))).padding(16).frame(width: 402)
}
