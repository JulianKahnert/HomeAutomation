import SwiftUI

/// Variant C: the automation explains itself. A chronological list of what the
/// server wrote and why (the `reason` field), optionally mixed with what it
/// observed (manual change, valve, sensor failure).
struct DecisionLogVariant: View {
    @State var roomFilter: String?
    @State var showsObservations = true

    private var entries: [LogEntry] {
        MockData.log.filter { entry in
            (roomFilter == nil || entry.roomID == roomFilter) && (showsObservations || entry.kind == .write)
        }
    }

    var body: some View {
        Screen(title: "Entscheidungen", subtitle: "Was der Server geschrieben hat und warum") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    filterChip("Alle", id: nil)
                    ForEach(MockData.rooms) { filterChip($0.name, id: $0.id) }
                }
            }
            Toggle("Beobachtungen und Pushes zeigen", isOn: $showsObservations)
                .font(.subheadline)

            Card {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0, !Calendar.current.isDate(entry.date, inSameDayAs: entries[index - 1].date) {
                        Text("GESTERN").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                    }
                    LogRow(entry: entry)
                    if index < entries.count - 1 { Divider() }
                }
            }
        }
    }

    private func filterChip(_ title: String, id: String?) -> some View {
        Button(title) { roomFilter = id }
            .buttonStyle(.plain)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(roomFilter == id ? Color.accentColor : Color.gray.opacity(0.2), in: .capsule)
            .foregroundStyle(roomFilter == id ? .white : .primary)
    }
}

struct LogRow: View {
    let entry: LogEntry
    var showsRoom = true

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(Fmt.time(entry.date))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            Image(systemName: entry.causeKind.symbol)
                .foregroundStyle(entry.causeKind.color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                if showsRoom {
                    Text(subject).font(.caption).foregroundStyle(.secondary)
                }
                Text(entry.action).font(.subheadline.weight(.semibold))
                HStack(spacing: 6) {
                    kindBadge
                    Text(entry.detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .opacity(entry.kind == .write ? 1 : 0.85)
    }

    private var subject: String {
        let room = MockData.room(entry.roomID).name
        guard let id = entry.radiatorID else { return room }
        return "\(room) · \(MockData.radiator(id).name)"
    }

    @ViewBuilder
    private var kindBadge: some View {
        switch entry.kind {
        case .write:
            Text(entry.reason ?? "")
                .font(.caption2.monospaced().weight(.semibold))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(entry.causeKind.color.opacity(0.15), in: .rect(cornerRadius: 4))
                .foregroundStyle(entry.causeKind.color)
        case .observation:
            Text("beobachtet")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [2, 2])))
                .foregroundStyle(.secondary)
        case .push:
            Label("Push", systemImage: "bell.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.yellow)
        }
    }
}

#Preview("C Entscheidungsprotokoll") {
    DecisionLogVariant().environment(\.locale, Fmt.de)
}

#Preview("C Entscheidungsprotokoll – Schlafzimmer") {
    DecisionLogVariant(roomFilter: "schlafzimmer").environment(\.locale, Fmt.de)
}
