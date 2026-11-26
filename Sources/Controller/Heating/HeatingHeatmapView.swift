//
//  HeatingHeatmapView.swift
//  ControllerFeatures
//
//  The week heatmap in Variante G "Leicht": room × day × six-hour segment as rounded cells, the value
//  only on selection, hatched = no actual value, no legend
//

import HAModels
import SwiftUI

struct HeatingHeatmapView: View {
    /// The rooms in the order of the bars.
    let rooms: [HeatingOverviewRoom]
    let cells: [HeatingHeatmapCell]
    let selectedPlaceId: String?
    /// The cell whose value is shown; set by a tap, preset in previews.
    @State var selection: Selection?

    struct Selection: Equatable {
        let placeId: String
        let day: Date
        let segment: Int
    }

    @Environment(\.colorScheme) private var scheme

    init(rooms: [HeatingOverviewRoom], cells: [HeatingHeatmapCell], selectedPlaceId: String?, selection: Selection? = nil) {
        self.rooms = rooms
        self.cells = cells
        self.selectedPlaceId = selectedPlaceId
        self._selection = State(initialValue: selection)
    }

    private static let segmentTitles = ["0–6", "6–12", "12–18", "18–24"]

    private var days: [Date] { Array(Set(cells.map(\.day))).sorted() }

    private func cell(_ placeId: String, _ day: Date, _ segment: Int) -> HeatingHeatmapCell? {
        cells.first { $0.placeId == placeId && $0.day == day && $0.segment == segment }
    }

    var body: some View {
        HeatingSection {
            Grid(horizontalSpacing: 4, verticalSpacing: 6) {
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    ForEach(days, id: \.self) { day in
                        Text(Self.weekday(day))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(rooms) { room in
                    GridRow {
                        Text(room.shortName)
                            .font(.caption.weight(room.placeId == selectedPlaceId ? .bold : .regular))
                            .lineLimit(1)
                            // Truncates a long name instead of pushing the grid past the screen edge.
                            .frame(maxWidth: 96, alignment: .leading)
                            .gridColumnAlignment(.leading)
                        ForEach(days, id: \.self) { day in
                            HStack(spacing: 2) {
                                ForEach(0..<4, id: \.self) { segment in
                                    cellView(room, day, segment)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        } header: {
            HStack(alignment: .firstTextBaseline) {
                Text("Woche")
                Spacer()
                // Reserves its line so the section does not jump when a value appears.
                Text(selectionText ?? " ")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } footer: {
            Text("Abweichung vom Plan je sechs Stunden. Schraffiert: kein Ist-Wert.")
        }
    }

    private func cellView(_ room: HeatingOverviewRoom, _ day: Date, _ segment: Int) -> some View {
        let placeId = room.placeId
        let value = cell(placeId, day, segment)?.delta
        let isSelected = selection == Selection(placeId: placeId, day: day, segment: segment)
        return Group {
            if let value {
                RoundedRectangle(cornerRadius: 3).fill(Self.color(value, scheme: scheme))
            } else {
                HeatingHatch(showsMark: false).clipShape(.rect(cornerRadius: 3))
            }
        }
        // Narrows on small screens, so the seven days always fit.
        .frame(minWidth: 3, maxWidth: 7, minHeight: 16, maxHeight: 16)
        .overlay {
            if isSelected { RoundedRectangle(cornerRadius: 3).strokeBorder(Color.primary, lineWidth: 1.5) }
        }
        .contentShape(Rectangle())
        .onTapGesture { selection = isSelected ? nil : Selection(placeId: placeId, day: day, segment: segment) }
        #if os(macOS)
        .onHover { if $0 { selection = Selection(placeId: placeId, day: day, segment: segment) } }
        #endif
        .accessibilityLabel(Self.accessibilityLabel(room.shortName, day, segment, value))
    }

    /// Grey inside the comfort band, blue or orange beyond it; the stronger the deviation, the deeper the tint.
    static func color(_ delta: Double, scheme: ColorScheme) -> Color {
        let base = HeatingPalette.color(forDelta: delta, scheme: scheme)
        if HeatingComfort(delta: delta) == .ok { return base.opacity(0.28) }
        let strength = min(abs(delta) / HeatingPalette.barScale, 1)
        // Dark mode needs a higher floor: a weak peach over a dark card turns brown.
        return base.opacity((scheme == .dark ? 0.6 : 0.4) + (scheme == .dark ? 0.4 : 0.6) * strength)
    }

    private var selectionText: String? {
        guard let selection, let room = rooms.first(where: { $0.placeId == selection.placeId }) else { return nil }
        let value = cell(selection.placeId, selection.day, selection.segment)?.delta
        return Self.accessibilityLabel(room.shortName, selection.day, selection.segment, value)
    }

    private static func accessibilityLabel(_ name: String, _ day: Date, _ segment: Int, _ value: Double?) -> String {
        "\(name) · \(weekday(day)) \(segmentTitles[segment]) Uhr · \(value.map(HeatingFormat.kelvin) ?? "keine Daten")"
    }

    private static func weekday(_ day: Date) -> String {
        HeatingFormat.weekday(day, calendar: HeatingOverviewBuilder.berlin)
    }
}

#Preview("Wochen-Heatmap") {
    HeatingHeatmapView(rooms: HeatingFeature.sorted(HeatingPreviewData.overviewRooms), cells: HeatingPreviewData.heatmap, selectedPlaceId: nil)
        .padding(16)
        .frame(width: 402)
}
