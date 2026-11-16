import Charts
import SwiftUI

/// Variant F, final design: variant E's content with the decisions of ticket 17 — iPhone one
/// column with the detail below the bars, Mac/iPad two columns, SF Symbol pins, blue/grey/orange
/// for Δ everywhere, system text styles, dark mode, and the empty states.
struct FinalVariant: View {
    var layout: FLayout = .compact
    var loadState: FLoadState = .loaded
    @State var selectedRoomID: String?
    @State var range: FRange = .day
    @State var pinID: String?
    @State var crosshair: Date?
    @State var heatmapCellID: String?

    var body: some View {
        switch loadState {
        case .loaded:
            loaded
        case .serverUnreachable:
            emptyState {
                ContentUnavailableView {
                    Label("Server nicht erreichbar", systemImage: "wifi.exclamationmark")
                } description: {
                    Text("Der HomeAutomation-Server antwortet nicht. Die Heizungsdaten kommen nur vom Server.")
                } actions: {
                    Button("Erneut versuchen") {}
                        .buttonStyle(.borderedProminent)
                }
            }
        case .noRooms:
            emptyState {
                ContentUnavailableView {
                    Label("Keine Räume konfiguriert", systemImage: "heater.vertical")
                } description: {
                    Text("Trage Räume mit Thermostaten in die Heizungskonfiguration in HomeAutomation-config ein und deploye sie mit „swift run“.")
                }
            }
        }
    }

    private var selectedRoom: FRoom? { selectedRoomID.map(FData.room) }

    private var selection: Binding<String?> {
        Binding(
            get: { selectedRoomID },
            set: { selectedRoomID = $0; pinID = nil; crosshair = nil }
        )
    }

    @ViewBuilder
    private var loaded: some View {
        FScreen(layout: layout) {
            switch layout {
            case .compact:
                VStack(alignment: .leading, spacing: 16) {
                    overviewCard
                    if let room = selectedRoom {
                        detailCard(room)
                    }
                    heatmapCard
                }
            case .regular:
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 16) {
                        overviewCard
                        heatmapCard
                    }
                    .frame(width: FLayout.leftColumnWidth)
                    if let room = selectedRoom {
                        detailCard(room)
                    } else {
                        FCard {
                            ContentUnavailableView(
                                "Raum wählen",
                                systemImage: "chart.bar.xaxis",
                                description: Text("Wähle links einen Balken, um Soll/Ist, Ventile und Ereignisse des Raums zu sehen.")
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .frame(maxHeight: .infinity)
                    }
                }
                // The placeholder grows to the height of the left column.
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var overviewCard: some View {
        FCard {
            FCardHeader(title: "Abweichung jetzt", subtitle: "Ist − Plan-Soll je Raum, kältester links")
            FDeltaBars(selectedRoomID: selection)
        }
    }

    private var heatmapCard: some View {
        FCard {
            FCardHeader(title: "Woche", subtitle: "Mittleres Δ je Raum und Tagesviertel")
            FWeekHeatmap(selectedRoomID: selectedRoomID, cellID: $heatmapCellID)
        }
    }

    private func detailCard(_ room: FRoom) -> some View {
        FCard {
            FRoomDetail(
                room: room, layout: layout, range: $range, pinID: $pinID, crosshair: $crosshair,
                onClose: layout == .compact ? { selection.wrappedValue = nil } : nil
            )
        }
    }

    private func emptyState(@ViewBuilder _ content: () -> some View) -> some View {
        // Straight on the grouped background, as iOS shows ContentUnavailableView in a list.
        FScreen(layout: layout, showsStand: false) {
            content()
                .frame(maxWidth: .infinity, minHeight: layout == .compact ? 560 : 480)
        }
    }
}

enum FLayout {
    /// iPhone: one column, the detail opens below the bars.
    case compact
    /// Mac and iPad: bars and heatmap left, the selected room's detail right.
    case regular

    static let leftColumnWidth: CGFloat = 420
    static let compactWidth: CGFloat = 402
    static let regularWidth: CGFloat = 1_120

    /// Plot width estimate for stacking pins; Swift Charts gives it only after layout.
    var plotWidth: CGFloat {
        switch self {
        case .compact: Self.compactWidth - 32 - 32 - 34
        case .regular: Self.regularWidth - 48 - Self.leftColumnWidth - 32 - 34
        }
    }
}

enum FLoadState {
    case loaded, serverUnreachable, noRooms
}

// MARK: - Colours, containers

/// Light/dark pair, resolved against the view's colour scheme (so previews can force dark).
struct FAdaptive: ShapeStyle {
    let light: Color
    let dark: Color

    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        (environment.colorScheme == .dark ? dark : light).resolve(in: environment)
    }
}

enum FColor {
    /// systemGroupedBackground / secondarySystemGroupedBackground / tertiary, as on iOS.
    static let grouped = FAdaptive(light: Color(red: 0.949, green: 0.949, blue: 0.969), dark: .black)
    static let card = FAdaptive(light: .white, dark: Color(red: 0.110, green: 0.110, blue: 0.118))
    static let raised = FAdaptive(light: .white, dark: Color(red: 0.173, green: 0.173, blue: 0.180))

    static let cold = Color.blue
    static let ok = Color.gray
    static let warm = Color.orange
    static let comfort = 0.5

    /// The one Δ colour rule shared by bars, heatmap and gap fill.
    static func delta(_ value: Double) -> Color {
        value < -comfort ? cold : value > comfort ? warm : ok
    }

    static func heat(_ value: Double) -> Color {
        guard abs(value) > comfort else { return ok.opacity(0.28) }
        let strength = min((abs(value) - comfort) / (3 - comfort), 1)
        return delta(value).opacity(0.35 + 0.6 * strength)
    }

    static let valve: [Color] = [.green, .mint]
}

struct FScreen<Content: View>: View {
    let layout: FLayout
    var showsStand = true
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Heizung").font(.largeTitle.bold())
                    if showsStand {
                        Text("Stand \(V3Fmt.dayTime(FData.now)) · ±0,5 K gilt als ok")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                content
            }
            .padding(16)
        }
        .background(FColor.grouped)
    }
}

struct FCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FColor.card, in: .rect(cornerRadius: 16))
    }
}

struct FCardHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

/// Wraps legend entries onto the next line instead of truncating them on the iPhone.
struct FFlow: Layout {
    var spacing: CGFloat = 12
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let points = arrange(bounds.width, subviews).points
        for (subview, point) in zip(subviews, points) {
            subview.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(_ maxWidth: CGFloat, _ subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return (CGSize(width: width, height: y + rowHeight), points)
    }
}

struct FSwatch: View {
    let style: AnyShapeStyle
    let label: String

    init(_ style: some ShapeStyle, _ label: String) {
        self.style = AnyShapeStyle(style)
        self.label = label
    }

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(style).frame(width: 12, height: 10)
            Text(label)
        }
    }
}

// MARK: - Δ bars

struct FDeltaBars: View {
    @Binding var selectedRoomID: String?

    private let rooms = FData.sortedRooms
    private let limit = 3.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            chart
                .frame(height: 230)
            VStack(alignment: .leading, spacing: 4) {
                FFlow {
                    FSwatch(FColor.cold, "zu kalt")
                    FSwatch(FColor.ok.opacity(0.6), "ok ±0,5 K")
                    FSwatch(FColor.warm, "zu warm")
                    HStack(spacing: 4) {
                        FHatch(showsMark: false).frame(width: 12, height: 10)
                        Text("kein Ist")
                    }
                }
                FFlow {
                    Text("Ist aus:")
                    Label("Raumsensor", systemImage: "thermometer.medium")
                    Label("Mittel der Thermostate", systemImage: "heater.vertical")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(FCompactLabel())
        }
    }

    private var chart: some View {
        Chart {
            RectangleMark(yStart: .value("Δ", -FColor.comfort), yEnd: .value("Δ", FColor.comfort))
                .foregroundStyle(FColor.ok.opacity(0.14))
            RuleMark(y: .value("Δ", 0))
                .foregroundStyle(Color.primary.opacity(0.55))
                .lineStyle(StrokeStyle(lineWidth: 1))
            ForEach(rooms) { room in
                bar(room)
            }
        }
        .chartYScale(domain: -(limit + 0.5)...(limit + 0.5))
        .chartYAxis {
            AxisMarks(position: .leading, values: [-3.0, 0, 3.0]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                AxisValueLabel {
                    let number = value.as(Double.self) ?? 0
                    Text(number == 0 ? "0 K" : number > 0 ? "+3" : "−3").monospacedDigit()
                }
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let short = value.as(String.self), let room = rooms.first(where: { $0.short == short }) {
                        VStack(spacing: 2) {
                            Text(short)
                                .font(.caption)
                                .fontWeight(room.id == selectedRoomID ? .bold : .regular)
                                .foregroundStyle(room.id == selectedRoomID ? .primary : .secondary)
                            Image(systemName: room.istSource.symbol)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    missingBoxes(proxy: proxy, geo: geo)
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(SpatialTapGesture().onEnded { tap in
                            guard let plot = proxy.plotFrame,
                                  let short: String = proxy.value(atX: tap.location.x - geo[plot].minX),
                                  let room = rooms.first(where: { $0.short == short }) else { return }
                            selectedRoomID = selectedRoomID == room.id ? nil : room.id
                        })
                }
            }
        }
    }

    @ChartContentBuilder
    private func bar(_ room: FRoom) -> some ChartContent {
        let dimmed = selectedRoomID != nil && selectedRoomID != room.id
        if let delta = room.delta {
            BarMark(x: .value("Raum", room.short), y: .value("Δ", min(max(delta, -limit), limit)), width: .ratio(0.6))
                .foregroundStyle(FColor.delta(delta).opacity(dimmed ? 0.3 : 0.9))
                .clipShape(.rect(cornerRadius: 3))
                .annotation(position: delta < 0 ? .bottom : .top, spacing: 3) {
                    Text(V3Fmt.kelvin(delta).replacingOccurrences(of: " K", with: ""))
                        .font(.caption.monospacedDigit())
                        .fontWeight(room.id == selectedRoomID ? .bold : .regular)
                        .foregroundStyle(dimmed ? .tertiary : .secondary)
                }
        } else {
            // Keeps the category on the axis; the hatched box is drawn in the overlay.
            BarMark(x: .value("Raum", room.short), yStart: .value("Δ", -0.6), yEnd: .value("Δ", 0.6), width: .ratio(0.6))
                .foregroundStyle(Color.clear)
        }
    }

    @ViewBuilder
    private func missingBoxes(proxy: ChartProxy, geo: GeometryProxy) -> some View {
        if let plot = proxy.plotFrame {
            let frame = geo[plot]
            ForEach(rooms.filter { $0.delta == nil }) { room in
                if let x = proxy.position(forX: room.short),
                   let top = proxy.position(forY: 0.6),
                   let bottom = proxy.position(forY: -0.6) {
                    FHatch(isSelected: room.id == selectedRoomID)
                        .frame(width: frame.width / CGFloat(rooms.count) * 0.6, height: bottom - top)
                        .opacity(selectedRoomID != nil && selectedRoomID != room.id ? 0.4 : 1)
                        .position(x: frame.minX + x, y: frame.minY + (top + bottom) / 2)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

/// Room or cell without Ist: hatched, dashed outline, optional "?". Selection in primary.
struct FHatch: View {
    var isSelected = false
    var showsMark = true

    var body: some View {
        ZStack {
            Canvas { context, size in
                var path = Path()
                var x = -size.height
                while x < size.width {
                    path.move(to: CGPoint(x: x, y: size.height))
                    path.addLine(to: CGPoint(x: x + size.height, y: 0))
                    x += 5
                }
                context.stroke(path, with: .color(.secondary.opacity(0.7)), lineWidth: 1)
            }
            .clipShape(.rect)
            Rectangle()
                .strokeBorder(isSelected ? Color.primary : .secondary, style: StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: [3, 2]))
            if showsMark {
                Text("?").font(.headline).foregroundStyle(.primary)
            }
        }
    }
}

struct FCompactLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}

// MARK: - Detail

struct FRoomDetail: View {
    let room: FRoom
    let layout: FLayout
    @Binding var range: FRange
    @Binding var pinID: String?
    @Binding var crosshair: Date?
    let onClose: (() -> Void)?

    private var domain: ClosedRange<Date> { range.domain }

    /// 7 T keeps every third sample, as the 30 min grid of the API would.
    private var samples: [FSample] {
        let visible = room.samples.filter { domain.contains($0.date) }
        guard range == .week else { return visible }
        return visible.enumerated().filter { $0.offset % 3 == 0 || $0.offset == visible.count - 1 }.map(\.element)
    }

    /// Plan pins only up to 24 h; over a week they would bury the rest.
    private var pins: [FEvent] {
        room.events.compactMap { event in
            guard range != .week || event.kind != .plan else { return nil }
            if domain.contains(event.date) { return event }
            guard let end = event.end, end > domain.lowerBound, event.date < domain.lowerBound else { return nil }
            var clipped = event
            clipped.pinDate = domain.lowerBound
            return clipped
        }
    }

    private var areas: [FEvent] {
        room.events.filter { event in
            guard let end = event.end else { return false }
            return end > domain.lowerBound && event.date < domain.upperBound
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(room.name).font(.headline)
                    Label("Ist: \(room.istSource.text)", systemImage: room.istSource.symbol)
                        .labelStyle(FCompactLabel())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let onClose {
                    Button("Schließen", systemImage: "xmark.circle.fill", action: onClose)
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .buttonStyle(.plain)
                }
            }

            FReadout(room: room, date: crosshair)

            Picker("Zeitraum", selection: $range) {
                ForEach(FRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: range) {
                pinID = nil
                if let date = crosshair, !domain.contains(date) { crosshair = nil }
            }

            FSollIstChart(room: room, range: range, samples: samples, pins: pins, areas: areas, plotWidth: layout.plotWidth, pinID: $pinID, crosshair: $crosshair)
            FSollIstLegend()

            Text("Ventil je Heizkörper")
                .font(.subheadline.weight(.semibold))
                .padding(.top, 8)
            FValveChart(room: room, range: range, samples: samples, pins: pins, areas: areas, crosshair: $crosshair)
        }
    }
}

/// Values at the crosshair, else now; sits above the chart so it never covers the lines.
struct FReadout: View {
    let room: FRoom
    let date: Date?

    var body: some View {
        let sample = date.map(room.sample(at:)) ?? room.current
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            value("Ist", V3Fmt.deg(sample.ist))
            value("Plan-Soll", V3Fmt.deg(sample.sollPlan))
            value("Δ", sample.delta.map(V3Fmt.kelvin) ?? "?", color: sample.delta.map(FColor.delta) ?? .secondary)
            Spacer(minLength: 0)
            Text(date == nil ? "jetzt" : V3Fmt.dayTime(sample.date))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func value(_ label: String, _ text: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(text).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(color)
        }
    }
}

/// Time axis shared by Soll/Ist and valve, so both charts line up.
func fTimeAxis(_ range: FRange) -> some AxisContent {
    let (component, count): (Calendar.Component, Int) = switch range {
    case .twoHours: (.minute, 30)
    case .day: (.hour, 6)
    case .week: (.day, 1)
    }
    return AxisMarks(values: .stride(by: component, count: count)) { value in
        AxisGridLine()
        AxisValueLabel(centered: range == .week) {
            if let date = value.as(Date.self) {
                Text(range == .week ? date.formatted(.dateTime.weekday(.short).locale(Fmt.de)) : Fmt.time(date))
                    .monospacedDigit()
            }
        }
    }
}

/// Same label width in both detail charts, so their plots and the shared crosshair line up.
func fYLabel(_ text: String) -> some View {
    Text(text).monospacedDigit().lineLimit(1).fixedSize().frame(width: 40, alignment: .trailing)
}

/// "Keine Daten im Zeitraum" inside the chart frame, so the frame and axes stay.
struct FNoData: View {
    var detail: String?

    var body: some View {
        VStack(spacing: 2) {
            Text("Keine Daten im Zeitraum").font(.subheadline.weight(.semibold))
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(FColor.card.opacity(0.92), in: .rect(cornerRadius: 8))
    }
}

struct FSollIstChart: View {
    let room: FRoom
    let range: FRange
    let samples: [FSample]
    let pins: [FEvent]
    let areas: [FEvent]
    let plotWidth: CGFloat
    @Binding var pinID: String?
    @Binding var crosshair: Date?

    private static let laneHeight: CGFloat = 24
    private static let pinWidth: CGFloat = 22
    private static let popoverWidth: CGFloat = 240

    private var domain: ClosedRange<Date> { range.domain }
    private var hasIst: Bool { samples.contains { $0.ist != nil } }

    /// Each pin takes the lowest lane that is free at its x, so close pins stack instead of overlapping.
    private var lanes: [String: Int] {
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        var lastX: [CGFloat] = []
        var result: [String: Int] = [:]
        for pin in pins {
            let x = CGFloat(pin.pinX.timeIntervalSince(domain.lowerBound) / span) * plotWidth
            let lane = lastX.firstIndex { x - $0 >= Self.pinWidth } ?? lastX.count
            if lane == lastX.count { lastX.append(x) } else { lastX[lane] = x }
            result[pin.id] = lane
        }
        return result
    }

    private var yDomain: ClosedRange<Double> {
        let values = samples.flatMap { [$0.sollPlan] + ($0.ist.map { [$0] } ?? []) }
        return ((values.min() ?? 16) - 1).rounded(.down)...((values.max() ?? 22) + 1).rounded(.up)
    }

    private var selectedPin: FEvent? { pins.first { $0.id == pinID } }

    var body: some View {
        let lanes = lanes
        let laneCount = max((lanes.values.max() ?? 0) + 1, 1)
        Chart {
            ForEach(areas) { area in
                RectangleMark(xStart: .value("Start", max(area.date, domain.lowerBound)), xEnd: .value("Ende", min(area.end!, domain.upperBound)))
                    .foregroundStyle(FColor.ok.opacity(0.16))
            }
            gap
            ForEach(samples, id: \.date) { sample in
                LineMark(x: .value("Zeit", sample.date), y: .value("°C", sample.sollPlan), series: .value("Serie", "Soll"))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
            }
            ForEach(samples.filter { $0.ist != nil }, id: \.date) { sample in
                LineMark(x: .value("Zeit", sample.date), y: .value("°C", sample.ist!), series: .value("Serie", "Ist"))
                    .foregroundStyle(Color.primary)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            ForEach(pins) { pin in
                let isSelected = pin.id == pinID
                RuleMark(x: .value("Zeit", pin.pinX))
                    .foregroundStyle(isSelected ? Color.primary.opacity(0.8) : Color.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: isSelected ? 1.5 : 1, dash: [2, 2]))
                    .annotation(position: .top, spacing: 4 + CGFloat(lanes[pin.id] ?? 0) * Self.laneHeight, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        FPinBadge(kind: pin.kind, isSelected: isSelected)
                    }
            }
            if let crosshair {
                let sample = room.sample(at: crosshair)
                RuleMark(x: .value("Zeit", crosshair))
                    .foregroundStyle(Color.primary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("Zeit", sample.date), y: .value("°C", sample.sollPlan))
                    .foregroundStyle(Color.secondary)
                    .symbolSize(30)
                if let ist = sample.ist {
                    PointMark(x: .value("Zeit", sample.date), y: .value("°C", ist))
                        .foregroundStyle(Color.primary)
                        .symbolSize(36)
                }
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: yDomain)
        .chartLegend(.hidden)
        .chartXAxis { fTimeAxis(range) }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel { fYLabel("\(value.as(Double.self).map { Int($0) } ?? 0)°") }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let plotAnchor = proxy.plotFrame {
                    let plot = geo[plotAnchor]
                    ZStack(alignment: .topLeading) {
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                                if drag.startLocation.y < plot.minY {
                                    selectPin(near: drag.startLocation.x - plot.minX, proxy: proxy)
                                } else if let date: Date = proxy.value(atX: drag.location.x - plot.minX) {
                                    crosshair = min(max(date, domain.lowerBound), domain.upperBound)
                                }
                            })
                            .onContinuousHover { phase in
                                if case .active(let point) = phase, point.y >= plot.minY,
                                   let date: Date = proxy.value(atX: point.x - plot.minX) {
                                    crosshair = min(max(date, domain.lowerBound), domain.upperBound)
                                }
                            }
                        if !hasIst {
                            FNoData(detail: room.lastIst.map { "letzter Ist-Wert \(V3Fmt.dayTime($0.date))" })
                                .position(x: plot.midX, y: plot.midY)
                        }
                        if let pin = selectedPin, let x = proxy.position(forX: pin.pinX) {
                            FPinPopover(event: pin)
                                .frame(width: Self.popoverWidth)
                                .fixedSize(horizontal: false, vertical: true)
                                .position(x: popoverX(plot.minX + x, in: plot), y: plot.minY + 44)
                        }
                    }
                }
            }
        }
        .padding(.top, CGFloat(laneCount) * Self.laneHeight + 4)
        .frame(height: 220 + CGFloat(laneCount) * Self.laneHeight)
    }

    /// Ist − Plan-Soll filled in the Δ colour; each class is its own series so the fill
    /// switches colour where the gap crosses ±0,5 K.
    @ChartContentBuilder
    private var gap: some ChartContent {
        ForEach([("kalt", FColor.cold, 0.3), ("ok", FColor.ok, 0.22), ("warm", FColor.warm, 0.34)], id: \.0) { name, color, opacity in
            ForEach(samples.filter { $0.ist != nil }, id: \.date) { sample in
                let ist = sample.ist!
                let matches = FColor.delta(ist - sample.sollPlan) == color
                AreaMark(
                    x: .value("Zeit", sample.date),
                    yStart: .value("°C", ist),
                    yEnd: .value("°C", matches ? sample.sollPlan : ist),
                    series: .value("Lücke", name)
                )
                .foregroundStyle(color.opacity(opacity))
            }
        }
    }

    private func selectPin(near x: CGFloat, proxy: ChartProxy) {
        let nearest = pins.min { a, b in
            abs((proxy.position(forX: a.pinX) ?? .infinity) - x) < abs((proxy.position(forX: b.pinX) ?? .infinity) - x)
        }
        guard let nearest, let pinX = proxy.position(forX: nearest.pinX), abs(pinX - x) < Self.pinWidth else { return }
        pinID = pinID == nearest.id ? nil : nearest.id
    }

    /// Hangs the popover beside its pin on the side with more room, so pin and latest values stay visible.
    private func popoverX(_ x: CGFloat, in plot: CGRect) -> CGFloat {
        let width = Self.popoverWidth
        let centre = x > plot.midX ? x - 10 - width / 2 : x + 10 + width / 2
        return min(max(centre, plot.minX + width / 2), plot.maxX - width / 2)
    }
}

struct FPinBadge: View {
    let kind: FEventKind
    var isSelected = false

    var body: some View {
        Image(systemName: kind.symbol)
            .font(.caption2.weight(.semibold))
            .imageScale(.small)
            .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .frame(width: 20, height: 20)
            .background(Circle().fill(FColor.raised))
            // Selection in primary, not the accent: blue stays reserved for "zu kalt".
            .overlay(Circle().strokeBorder(isSelected ? Color.primary : Color.secondary.opacity(0.45), lineWidth: isSelected ? 2 : 1))
    }
}

struct FPinPopover: View {
    let event: FEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(event.kind.label + " · " + V3Fmt.dayTime(event.date) + (event.end.map { $0 >= FData.now ? " – jetzt" : " – \(Fmt.time($0))" } ?? ""))
                    .font(.caption.weight(.semibold).monospacedDigit())
            } icon: {
                Image(systemName: event.kind.symbol).font(.caption)
            }
            .labelStyle(FCompactLabel())
            Text(event.title)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Text("Grund: \(event.reason)")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FColor.raised, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.3)))
        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
    }
}

struct FSollIstLegend: View {
    var body: some View {
        FFlow {
            HStack(spacing: 4) {
                Rectangle().stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 2])).frame(width: 14, height: 0.1)
                Text("Plan-Soll")
            }
            HStack(spacing: 4) {
                Capsule().fill(Color.primary).frame(width: 14, height: 2.5)
                Text("Ist")
            }
            FSwatch(FColor.cold.opacity(0.35), "Lücke kalt")
            FSwatch(FColor.warm.opacity(0.4), "Lücke warm")
            FSwatch(FColor.ok.opacity(0.3), "Fenster/Kamin-Dauer")
            ForEach(FEventKind.allCases, id: \.self) { kind in
                Label(kind.label, systemImage: kind.symbol)
            }
        }
        .labelStyle(FCompactLabel())
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

struct FValveChart: View {
    let room: FRoom
    let range: FRange
    let samples: [FSample]
    let pins: [FEvent]
    let areas: [FEvent]
    @Binding var crosshair: Date?

    private var domain: ClosedRange<Date> { range.domain }
    private var hasValves: Bool { samples.contains { $0.valves.contains { $0 != nil } } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(areas) { area in
                    RectangleMark(xStart: .value("Start", max(area.date, domain.lowerBound)), xEnd: .value("Ende", min(area.end!, domain.upperBound)))
                        .foregroundStyle(FColor.ok.opacity(0.16))
                }
                ForEach(pins) { pin in
                    RuleMark(x: .value("Zeit", pin.pinX))
                        .foregroundStyle(Color.secondary.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                }
                ForEach(Array(room.radiators.enumerated()), id: \.offset) { index, radiator in
                    ForEach(samples.filter { $0.valves[index] != nil }, id: \.date) { sample in
                        LineMark(x: .value("Zeit", sample.date), y: .value("%", sample.valves[index]!), series: .value("Heizkörper", radiator))
                            .interpolationMethod(.stepEnd)
                            .foregroundStyle(FColor.valve[index % FColor.valve.count])
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: index == 0 ? [] : [6, 2]))
                    }
                }
                if let crosshair {
                    RuleMark(x: .value("Zeit", crosshair))
                        .foregroundStyle(Color.primary.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            .chartXScale(domain: domain)
            .chartYScale(domain: 0...100)
            .chartLegend(.hidden)
            .chartPlotStyle { $0.clipped() }
            .chartXAxis { fTimeAxis(range) }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel { fYLabel("\(value.as(Int.self) ?? 0) %") }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    if let plotAnchor = proxy.plotFrame {
                        let plot = geo[plotAnchor]
                        ZStack {
                            Rectangle().fill(.clear).contentShape(Rectangle())
                                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                                    if let date: Date = proxy.value(atX: drag.location.x - plot.minX) {
                                        crosshair = min(max(date, domain.lowerBound), domain.upperBound)
                                    }
                                })
                            if !hasValves {
                                FNoData().position(x: plot.midX, y: plot.midY)
                            }
                        }
                    }
                }
            }
            .frame(height: 110)

            let sample = crosshair.map(room.sample(at:)) ?? room.current
            FFlow {
                ForEach(Array(room.radiators.enumerated()), id: \.offset) { index, radiator in
                    HStack(spacing: 4) {
                        Capsule().fill(FColor.valve[index % FColor.valve.count]).frame(width: 14, height: 2.5)
                        Text(radiator)
                        Text(sample.valves[index].map { "\(Int($0)) %" } ?? "–")
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Week heatmap

struct FWeekHeatmap: View {
    let selectedRoomID: String?
    @Binding var cellID: String?

    private let rooms = FData.sortedRooms
    private let labelWidth: CGFloat = 52

    private var selectedCell: FCell? { FData.heatmap.first { $0.id == cellID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 2) {
                HStack(spacing: 0) {
                    Color.clear.frame(width: labelWidth, height: 1)
                    ForEach(FData.heatmapDays, id: \.self) { day in
                        Text(day.formatted(.dateTime.weekday(.short).locale(Fmt.de)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(rooms) { room in
                    HStack(spacing: 0) {
                        Text(room.short)
                            .font(.caption)
                            .fontWeight(room.id == selectedRoomID ? .bold : .regular)
                            .foregroundStyle(room.id == selectedRoomID ? .primary : .secondary)
                            .lineLimit(1)
                            .frame(width: labelWidth, alignment: .leading)
                        ForEach(FData.heatmapDays, id: \.self) { day in
                            HStack(spacing: 1) {
                                ForEach(cells(room.id, day)) { cell in
                                    cellView(cell)
                                }
                            }
                            .padding(.horizontal, 1.5)
                        }
                    }
                }
            }

            Group {
                if let cell = selectedCell, let room = rooms.first(where: { $0.id == cell.roomID }) {
                    HStack(spacing: 4) {
                        Text("\(room.name) · \(cell.day.formatted(.dateTime.weekday(.short).day().month(.twoDigits).locale(Fmt.de))) \(cell.segmentLabel) ·")
                        Text(cell.delta.map(V3Fmt.kelvin) ?? "kein Ist (mehr als die Hälfte fehlt)")
                            .fontWeight(.semibold)
                            .foregroundStyle(cell.delta.map(FColor.delta) ?? .secondary)
                    }
                    .monospacedDigit()
                } else {
                    Text("Feld antippen zeigt den Wert. Je Tag: 0–6 · 6–12 · 12–18 · 18–24 Uhr")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            FFlow {
                HStack(spacing: 4) {
                    Text("−3 K").monospacedDigit()
                    LinearGradient(
                        colors: [FColor.heat(-3), FColor.heat(-1), FColor.heat(0), FColor.heat(1), FColor.heat(3)],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: 96, height: 10)
                    .clipShape(.rect(cornerRadius: 2))
                    Text("+3 K").monospacedDigit()
                }
                HStack(spacing: 4) {
                    FHatch(showsMark: false).frame(width: 12, height: 10)
                    Text("kein Ist")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func cells(_ roomID: String, _ day: Date) -> [FCell] {
        FData.heatmap.filter { $0.roomID == roomID && $0.day == day }.sorted { $0.segment < $1.segment }
    }

    private func cellView(_ cell: FCell) -> some View {
        Group {
            if let delta = cell.delta {
                RoundedRectangle(cornerRadius: 2).fill(FColor.heat(delta))
            } else {
                FHatch(showsMark: false).clipShape(.rect(cornerRadius: 2))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 18)
        .overlay {
            if cell.id == cellID {
                RoundedRectangle(cornerRadius: 2).strokeBorder(Color.primary, lineWidth: 1.5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { cellID = cellID == cell.id ? nil : cell.id }
        .onHover { inside in if inside { cellID = cell.id } }
    }
}

// MARK: - Previews

private extension View {
    func fPreview(_ layout: FLayout, _ scheme: ColorScheme) -> some View {
        frame(width: layout == .compact ? FLayout.compactWidth : FLayout.regularWidth)
            .environment(\.colorScheme, scheme)
            .environment(\.locale, Fmt.de)
        #if os(macOS)
            // The snapshot window is never key; without this every control renders inactive grey.
            .environment(\.controlActiveState, .key)
        #endif
    }
}

private enum FScenario {
    static let arbeitPin = FData.room("arbeitszimmer").events.last { $0.kind == .observed }?.id
    /// Schlafzimmer: two radiators, so the valve chart shows one line per radiator.
    static let schlafPin = FData.room("schlafzimmer").events.last { $0.kind == .window }?.id
    static let schlafCell = FData.heatmap.first { $0.roomID == "schlafzimmer" && $0.day == FData.d(13, "00:00") && $0.segment == 1 }?.id

    static func overview(_ layout: FLayout) -> FinalVariant {
        FinalVariant(layout: layout)
    }

    static func detail24h(_ layout: FLayout) -> FinalVariant {
        FinalVariant(layout: layout, selectedRoomID: "arbeitszimmer", range: .day, pinID: arbeitPin, crosshair: FData.d(15, "18:30"))
    }

    static func week(_ layout: FLayout) -> FinalVariant {
        FinalVariant(layout: layout, selectedRoomID: "schlafzimmer", range: .week, pinID: schlafPin, crosshair: FData.d(13, "07:20"), heatmapCellID: schlafCell)
    }

    static func noData(_ layout: FLayout) -> FinalVariant {
        FinalVariant(layout: layout, selectedRoomID: "kaminzimmer", range: .day)
    }
}

#Preview("F iphone hell uebersicht") { FScenario.overview(.compact).fPreview(.compact, .light) }
#Preview("F iphone dunkel uebersicht") { FScenario.overview(.compact).fPreview(.compact, .dark) }
#Preview("F mac hell uebersicht") { FScenario.overview(.regular).fPreview(.regular, .light) }
#Preview("F mac dunkel uebersicht") { FScenario.overview(.regular).fPreview(.regular, .dark) }

#Preview("F iphone hell detail 24h") { FScenario.detail24h(.compact).fPreview(.compact, .light) }
#Preview("F iphone dunkel detail 24h") { FScenario.detail24h(.compact).fPreview(.compact, .dark) }
#Preview("F mac hell detail 24h") { FScenario.detail24h(.regular).fPreview(.regular, .light) }
#Preview("F mac dunkel detail 24h") { FScenario.detail24h(.regular).fPreview(.regular, .dark) }

#Preview("F iphone hell detail 7t") { FScenario.week(.compact).fPreview(.compact, .light) }
#Preview("F iphone dunkel detail 7t") { FScenario.week(.compact).fPreview(.compact, .dark) }
#Preview("F mac hell detail 7t") { FScenario.week(.regular).fPreview(.regular, .light) }
#Preview("F mac dunkel detail 7t") { FScenario.week(.regular).fPreview(.regular, .dark) }

#Preview("F iphone hell raum ohne daten") { FScenario.noData(.compact).fPreview(.compact, .light) }
#Preview("F iphone dunkel raum ohne daten") { FScenario.noData(.compact).fPreview(.compact, .dark) }
#Preview("F mac hell raum ohne daten") { FScenario.noData(.regular).fPreview(.regular, .light) }
#Preview("F mac dunkel raum ohne daten") { FScenario.noData(.regular).fPreview(.regular, .dark) }

#Preview("F iphone hell server nicht erreichbar") { FinalVariant(layout: .compact, loadState: .serverUnreachable).fPreview(.compact, .light) }
#Preview("F iphone dunkel server nicht erreichbar") { FinalVariant(layout: .compact, loadState: .serverUnreachable).fPreview(.compact, .dark) }
#Preview("F mac hell server nicht erreichbar") { FinalVariant(layout: .regular, loadState: .serverUnreachable).fPreview(.regular, .light) }
#Preview("F mac dunkel server nicht erreichbar") { FinalVariant(layout: .regular, loadState: .serverUnreachable).fPreview(.regular, .dark) }

#Preview("F iphone hell keine raeume") { FinalVariant(layout: .compact, loadState: .noRooms).fPreview(.compact, .light) }
#Preview("F iphone dunkel keine raeume") { FinalVariant(layout: .compact, loadState: .noRooms).fPreview(.compact, .dark) }
#Preview("F mac hell keine raeume") { FinalVariant(layout: .regular, loadState: .noRooms).fPreview(.regular, .light) }
#Preview("F mac dunkel keine raeume") { FinalVariant(layout: .regular, loadState: .noRooms).fPreview(.regular, .dark) }
