import Foundation

/// Hardcoded scenario: Sunday 15.11.2026, 22:40, the last 24 hours of six rooms.
/// Every scenario the debug views must explain appears at least once:
/// - Küche: window open → Modus Aus (cold radiator because of the window)
/// - Schlafzimmer: plan setback at night; the right radiator was changed by hand
/// - Arbeitszimmer: offset +2,0 °C, so Eve-Ist differs from the room sensor
/// - Kaminzimmer: fireplace on, only one of two radiators on the fireplace list
/// - Esszimmer: external room sensor failed
/// - Bad OG: valve stuck at 0 % although Soll > Ist
public enum MockData {
    static let calendar = Calendar.current
    public static let now: Date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 22, minute: 40))!
    static let start = now.addingTimeInterval(-24 * 3_600)
    static let domain = start...now

    /// Clock time within the last 24 h: today if not after now, else yesterday.
    static func t(_ hhmm: String) -> Date {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        var date = calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: now)!
        if date > now { date = date.addingTimeInterval(-86_400) }
        return date
    }

    static let grid: [Date] = stride(from: 0.0, through: 24 * 3_600, by: 600).map { start.addingTimeInterval($0) }

    /// Linear interpolation between keys on a 10-min grid, rounded like the device reports.
    static func curve(_ keys: [(Date, Double)], step: Double) -> [Sample] {
        let keys = [(start, keys[0].1)] + keys
        return grid.map { date in
            let after = keys.firstIndex { $0.0 >= date } ?? keys.count - 1
            let before = max(after - 1, 0)
            let (d0, v0) = keys[before]
            let (d1, v1) = keys[after]
            let fraction = d1 > d0 ? min(max(date.timeIntervalSince(d0) / d1.timeIntervalSince(d0), 0), 1) : 1
            let value = v0 + (v1 - v0) * fraction
            return Sample(date: date, value: (value / step).rounded() * step)
        }
    }

    /// Step series: the value of the last key at or before each grid point.
    static func steps(_ keys: [(Date, Double)]) -> [Sample] {
        let keys = [(start, keys[0].1)] + keys
        return grid.map { date in
            Sample(date: date, value: keys.last { $0.0 <= date }!.1)
        }
    }

    static func open(_ from: String, _ to: String?) -> DateInterval {
        DateInterval(start: t(from), end: to.map(t) ?? now)
    }

    // MARK: Outside and heat pump (house-wide)

    static let outside = curve([
        (t("02:00"), 1.5), (t("06:30"), 0.0), (t("14:00"), 7.0), (t("19:00"), 3.5), (t("22:40"), 1.5),
    ], step: 0.1)

    /// Estimated, not read in v1 (ticket 15): IDA setback 23:00–05:30, hot water 13:00–14:00.
    static let heatPumpDelivering: [DateInterval] = [
        open("05:30", "13:00"), open("14:00", nil),
    ]

    // MARK: Rooms

    static let kueche = Room(
        id: "kueche", name: "Küche",
        windows: [WindowContact(name: "Fenster Küche", openIntervals: [open("12:10", "12:25"), open("22:25", nil)])],
        sensor: RoomSensor(name: "Küche Sensor", values: curve([
            (t("06:00"), 19.4), (t("08:00"), 20.8), (t("12:10"), 20.9), (t("12:25"), 18.6), (t("13:30"), 20.7),
            (t("22:00"), 20.6), (t("22:25"), 20.4), (t("22:30"), 18.4),
        ], step: 0.1), failedSince: nil),
        fireplaceOn: [],
        plan: [PlanPoint(time: "06:00", soll: 21, label: "Tag"), PlanPoint(time: "22:00", soll: 18, label: "Nacht")],
        activePlanIndex: 1,
        radiators: [Radiator(
            id: "kueche-1", name: "Heizung Küche", roomID: "kueche", offset: 0, isOnFireplaceList: false,
            eveIst: curve([
                (t("06:00"), 18.5), (t("08:00"), 21.0), (t("12:10"), 21.0), (t("12:25"), 19.5), (t("13:30"), 21.0),
                (t("22:25"), 20.5), (t("22:30"), 19.0),
            ], step: 0.5),
            soll: steps([(t("23:00"), 18), (t("06:00"), 21), (t("22:00"), 18)]),
            valve: steps([(t("23:00"), 5), (t("06:00"), 70), (t("08:00"), 25), (t("12:10"), 0), (t("12:25"), 80), (t("13:30"), 25), (t("22:00"), 0)]),
            offIntervals: [open("12:10", "12:25"), open("22:25", nil)],
            status: .cold,
            causes: [
                Cause(kind: .window, title: "Fenster Küche offen", detail: "Nach 10 s schaltet der Server alle Heizkörper des Raums aus: Modus Aus (Active = 0).", since: t("22:25"), until: "Beim Schließen sofort Plan: Nacht 18,0 °C"),
                Cause(kind: .planSetback, title: "Danach: Plan Nacht 18,0 °C", detail: "Schaltpunkt 22:00; Tag 21,0 °C ab 06:00.", since: t("22:00")),
            ]
        )]
    )

    static let schlafzimmer = Room(
        id: "schlafzimmer", name: "Schlafzimmer",
        windows: [WindowContact(name: "Fenster Schlafzimmer", openIntervals: [open("07:10", "07:30")])],
        sensor: RoomSensor(name: "Schlafzimmer Sensor", values: curve([
            (t("06:30"), 16.4), (t("08:30"), 19.6), (t("22:00"), 19.8), (t("22:30"), 19.1),
        ], step: 0.1), failedSince: nil),
        fireplaceOn: [],
        plan: [PlanPoint(time: "06:30", soll: 20, label: "Morgen"), PlanPoint(time: "22:00", soll: 16, label: "Nacht")],
        activePlanIndex: 1,
        radiators: [
            Radiator(
                id: "schlaf-links", name: "Heizung links", roomID: "schlafzimmer", offset: 0.5, isOnFireplaceList: false,
                eveIst: curve([(t("06:30"), 16.5), (t("08:30"), 20.5), (t("22:00"), 20.5), (t("22:30"), 18.5)], step: 0.5),
                soll: steps([(t("23:00"), 16.5), (t("06:30"), 20.5), (t("22:00"), 16.5)]),
                valve: steps([(t("23:00"), 0), (t("06:30"), 65), (t("08:30"), 20), (t("22:00"), 0)]),
                offIntervals: [open("07:10", "07:30")],
                status: .cold,
                causes: [
                    Cause(kind: .planSetback, title: "Plan-Absenkung Nacht", detail: "Plan 16,0 °C + Offset +0,5 °C = Soll 16,5 °C; Eve-Ist 18,5 °C liegt darüber, das Ventil bleibt zu.", since: t("22:00"), until: "Schaltpunkt 06:30 → 20,0 °C"),
                ]
            ),
            Radiator(
                id: "schlaf-rechts", name: "Heizung rechts", roomID: "schlafzimmer", offset: 0, isOnFireplaceList: false,
                eveIst: curve([(t("06:30"), 16.5), (t("08:30"), 20.0), (t("22:00"), 20.0), (t("22:10"), 19.5), (t("22:30"), 19.0)], step: 0.5),
                soll: steps([(t("23:00"), 16), (t("06:30"), 20), (t("22:00"), 16), (t("22:10"), 19)]),
                valve: steps([(t("23:00"), 0), (t("06:30"), 60), (t("08:30"), 20), (t("22:00"), 0), (t("22:15"), 40)]),
                offIntervals: [open("07:10", "07:30")],
                status: .warm,
                causes: [
                    Cause(kind: .manual, title: "Von Hand auf 19,0 °C gestellt", detail: "Soll änderte sich ohne Schreibzugriff des Servers (am Gerät oder in Apple Home).", since: t("22:10"), until: "Gilt bis Schaltpunkt 06:30 → 20,0 °C"),
                    Cause(kind: .planSetback, title: "Plan wäre Nacht 16,0 °C", detail: "Server hat um 22:00 16,0 °C geschrieben.", since: t("22:00")),
                ]
            ),
        ]
    )

    static let arbeitszimmer = Room(
        id: "arbeitszimmer", name: "Arbeitszimmer",
        windows: [WindowContact(name: "Fenster Arbeitszimmer", openIntervals: [])],
        sensor: RoomSensor(name: "Arbeitszimmer Sensor", values: curve([
            (t("07:00"), 17.9), (t("09:30"), 20.4), (t("16:00"), 20.9), (t("20:50"), 20.6),
        ], step: 0.1), failedSince: nil),
        fireplaceOn: [],
        plan: [PlanPoint(time: "07:00", soll: 21, label: "Tag"), PlanPoint(time: "23:00", soll: 18, label: "Nacht")],
        activePlanIndex: 0,
        radiators: [Radiator(
            id: "arbeit-1", name: "Heizung Arbeitszimmer", roomID: "arbeitszimmer", offset: 2.0, isOnFireplaceList: false,
            eveIst: curve([(t("07:00"), 19.5), (t("09:30"), 22.5), (t("16:00"), 23.0), (t("20:50"), 22.5)], step: 0.5),
            soll: steps([(t("23:00"), 20), (t("07:00"), 23)]),
            valve: steps([(t("23:00"), 5), (t("07:00"), 85), (t("09:30"), 40), (t("16:00"), 20), (t("19:20"), 35)]),
            offIntervals: [],
            status: .warm,
            causes: [
                Cause(kind: .heating, title: "Heizt nach Plan", detail: "Plan Tag 21,0 °C + Offset +2,0 °C = Soll 23,0 °C.", since: t("07:00"), until: "Schaltpunkt 23:00 → 18,0 °C"),
                Cause(kind: .offset, title: "Eve-Ist 22,5 °C, Raum 20,6 °C", detail: "Die Eve misst am Heizkörper 1,9 °C wärmer als der Raumsensor; der Offset +2,0 °C gleicht das aus.", since: nil),
            ]
        )]
    )

    static let kaminzimmer = Room(
        id: "kaminzimmer", name: "Kaminzimmer",
        windows: [WindowContact(name: "Terrassentür", openIntervals: [])],
        sensor: RoomSensor(name: "Kaminzimmer Sensor", values: curve([
            (t("07:00"), 18.6), (t("10:00"), 20.8), (t("19:30"), 20.9), (t("21:00"), 22.6), (t("22:10"), 23.4),
        ], step: 0.1), failedSince: nil),
        fireplaceOn: [open("19:30", nil)],
        plan: [PlanPoint(time: "07:00", soll: 21, label: "Tag"), PlanPoint(time: "23:00", soll: 18, label: "Nacht")],
        activePlanIndex: 0,
        radiators: [
            Radiator(
                id: "kamin-fenster", name: "Heizung Fenster", roomID: "kaminzimmer", offset: 1.0, isOnFireplaceList: true,
                eveIst: curve([(t("07:00"), 19.0), (t("10:00"), 22.0), (t("19:30"), 22.0), (t("21:00"), 21.0), (t("22:10"), 21.5)], step: 0.5),
                soll: steps([(t("23:00"), 19), (t("07:00"), 22)]),
                valve: steps([(t("23:00"), 0), (t("07:00"), 75), (t("10:00"), 30), (t("19:30"), 0)]),
                offIntervals: [open("19:30", nil)],
                status: .cold,
                causes: [
                    Cause(kind: .fireplace, title: "Kamin an", detail: "Heizkörper steht auf der Kamin-Liste: Modus Aus (Active = 0).", since: t("19:30"), until: "Auto-Ende 03:30 (8 h) mit Push"),
                ]
            ),
            Radiator(
                id: "kamin-tuer", name: "Heizung Tür", roomID: "kaminzimmer", offset: 0, isOnFireplaceList: false,
                eveIst: curve([(t("07:00"), 18.5), (t("10:00"), 21.0), (t("19:30"), 21.0), (t("21:00"), 22.5), (t("22:10"), 23.0)], step: 0.5),
                soll: steps([(t("23:00"), 18), (t("07:00"), 21)]),
                valve: steps([(t("23:00"), 0), (t("07:00"), 70), (t("10:00"), 25), (t("20:15"), 0)]),
                offIntervals: [],
                status: .cold,
                causes: [
                    Cause(kind: .valveClosed, title: "Raum warm genug", detail: "Eve-Ist 23,0 °C über Soll 21,0 °C, der Thermostat schließt das Ventil selbst. Nicht auf der Kamin-Liste, es gilt der Plan.", since: t("20:15")),
                ]
            ),
        ]
    )

    static let esszimmer = Room(
        id: "esszimmer", name: "Esszimmer",
        windows: [WindowContact(name: "Fenster Esszimmer", openIntervals: [])],
        sensor: RoomSensor(name: "Esszimmer Sensor", values: curve([
            (t("06:00"), 18.2), (t("09:00"), 20.3), (t("18:20"), 20.5),
        ], step: 0.1).filter { $0.date <= t("18:20") }, failedSince: t("21:20")),
        fireplaceOn: [],
        plan: [PlanPoint(time: "06:00", soll: 21, label: "Tag"), PlanPoint(time: "22:00", soll: 18, label: "Nacht")],
        activePlanIndex: 1,
        radiators: [Radiator(
            id: "ess-1", name: "Heizung Esszimmer", roomID: "esszimmer", offset: 1.0, isOnFireplaceList: false,
            eveIst: curve([(t("06:00"), 19.0), (t("09:00"), 22.0), (t("22:00"), 22.0), (t("22:30"), 20.5)], step: 0.5),
            soll: steps([(t("23:00"), 19), (t("06:00"), 22), (t("22:00"), 19)]),
            valve: steps([(t("23:00"), 0), (t("06:00"), 70), (t("09:00"), 25), (t("22:00"), 0)]),
            offIntervals: [],
            status: .warning,
            causes: [
                Cause(kind: .sensorFailure, title: "Raumsensor ausgefallen", detail: "Esszimmer Sensor: kein Wert seit 18:20 (> 3 h), Push um 21:20. Raum-Ist unbekannt; die Regelung ändert sich nicht (Offset ist statisch).", since: t("21:20")),
                Cause(kind: .planSetback, title: "Plan-Absenkung Nacht", detail: "Plan 18,0 °C + Offset +1,0 °C = Soll 19,0 °C.", since: t("22:00"), until: "Schaltpunkt 06:00 → 21,0 °C"),
            ]
        )]
    )

    static let badOG = Room(
        id: "bad-og", name: "Bad OG",
        windows: [WindowContact(name: "Fenster Bad OG", openIntervals: [open("06:50", "07:05")])],
        sensor: RoomSensor(name: "Bad OG Sensor", values: curve([
            (t("05:30"), 19.0), (t("07:30"), 21.6), (t("09:00"), 21.4), (t("14:10"), 20.2), (t("21:30"), 18.6),
        ], step: 0.1), failedSince: nil),
        fireplaceOn: [],
        plan: [
            PlanPoint(time: "05:30", soll: 22, label: "Morgen"), PlanPoint(time: "09:00", soll: 19, label: "Tag"),
            PlanPoint(time: "17:00", soll: 22, label: "Abend"), PlanPoint(time: "23:00", soll: 18, label: "Nacht"),
        ],
        activePlanIndex: 2,
        radiators: [Radiator(
            id: "bad-1", name: "Heizung Bad", roomID: "bad-og", offset: 0, isOnFireplaceList: false,
            eveIst: curve([(t("05:30"), 19.5), (t("07:30"), 22.0), (t("09:00"), 22.0), (t("14:10"), 20.5), (t("21:10"), 19.0)], step: 0.5),
            soll: steps([(t("23:00"), 18), (t("05:30"), 22), (t("09:00"), 19), (t("17:00"), 22)]),
            valve: steps([(t("23:00"), 0), (t("05:30"), 80), (t("07:30"), 30), (t("09:00"), 10), (t("14:10"), 0)]),
            offIntervals: [open("06:50", "07:05")],
            status: .warning,
            causes: [
                Cause(kind: .valveClosed, title: "Ventil 0 %, obwohl Soll > Ist", detail: "Soll 22,0 °C seit 17:00, Eve-Ist 19,0 °C, Ventil seit 14:10 bei 0 %. Kein Fenster, kein Kamin, Modus Heizen, Wärmepumpe liefert (geschätzt): Ventil hängt oder Thermostat reagiert nicht.", since: t("14:10")),
            ]
        )]
    )

    public static let rooms: [Room] = [kueche, schlafzimmer, kaminzimmer, esszimmer, arbeitszimmer, badOG]
    public static var radiators: [Radiator] { rooms.flatMap(\.radiators) }

    static func room(_ id: String) -> Room { rooms.first { $0.id == id }! }
    static func radiator(_ id: String) -> Radiator { radiators.first { $0.id == id }! }

    // MARK: Action log (server writes with `reason`) plus derived observations

    public static let log: [LogEntry] = [
        LogEntry(date: t("23:00"), roomID: "arbeitszimmer", radiatorID: "arbeit-1", kind: .write, action: "Soll 20,0 °C", reason: "plan", detail: "Nacht 18,0 °C + Offset +2,0 °C", causeKind: .planSetback),
        LogEntry(date: t("23:00"), roomID: "kaminzimmer", radiatorID: "kamin-fenster", kind: .write, action: "Soll 19,0 °C", reason: "plan", detail: "Nacht 18,0 °C + Offset +1,0 °C", causeKind: .planSetback),
        LogEntry(date: t("23:00"), roomID: "kaminzimmer", radiatorID: "kamin-tuer", kind: .write, action: "Soll 18,0 °C", reason: "plan", detail: "Nacht 18,0 °C + Offset 0", causeKind: .planSetback),
        LogEntry(date: t("23:00"), roomID: "bad-og", radiatorID: "bad-1", kind: .write, action: "Soll 18,0 °C", reason: "plan", detail: "Nacht 18,0 °C + Offset 0", causeKind: .planSetback),
        LogEntry(date: t("05:30"), roomID: "bad-og", radiatorID: "bad-1", kind: .write, action: "Soll 22,0 °C", reason: "plan", detail: "Morgen 22,0 °C + Offset 0", causeKind: .heating),
        LogEntry(date: t("06:00"), roomID: "kueche", radiatorID: "kueche-1", kind: .write, action: "Soll 21,0 °C", reason: "plan", detail: "Tag 21,0 °C + Offset 0", causeKind: .heating),
        LogEntry(date: t("06:00"), roomID: "esszimmer", radiatorID: "ess-1", kind: .write, action: "Soll 22,0 °C", reason: "plan", detail: "Tag 21,0 °C + Offset +1,0 °C", causeKind: .heating),
        LogEntry(date: t("06:30"), roomID: "schlafzimmer", radiatorID: "schlaf-links", kind: .write, action: "Soll 20,5 °C", reason: "plan", detail: "Morgen 20,0 °C + Offset +0,5 °C", causeKind: .heating),
        LogEntry(date: t("06:30"), roomID: "schlafzimmer", radiatorID: "schlaf-rechts", kind: .write, action: "Soll 20,0 °C", reason: "plan", detail: "Morgen 20,0 °C + Offset 0", causeKind: .heating),
        LogEntry(date: t("06:50"), roomID: "bad-og", radiatorID: "bad-1", kind: .write, action: "Modus Aus (Active = 0)", reason: "fenster", detail: "Fenster Bad OG 10 s offen", causeKind: .window),
        LogEntry(date: t("07:00"), roomID: "arbeitszimmer", radiatorID: "arbeit-1", kind: .write, action: "Soll 23,0 °C", reason: "plan", detail: "Tag 21,0 °C + Offset +2,0 °C", causeKind: .heating),
        LogEntry(date: t("07:00"), roomID: "kaminzimmer", radiatorID: "kamin-fenster", kind: .write, action: "Soll 22,0 °C", reason: "plan", detail: "Tag 21,0 °C + Offset +1,0 °C", causeKind: .heating),
        LogEntry(date: t("07:00"), roomID: "kaminzimmer", radiatorID: "kamin-tuer", kind: .write, action: "Soll 21,0 °C", reason: "plan", detail: "Tag 21,0 °C + Offset 0", causeKind: .heating),
        LogEntry(date: t("07:05"), roomID: "bad-og", radiatorID: "bad-1", kind: .write, action: "Modus Heizen, Soll 22,0 °C", reason: "fensterZu", detail: "Fenster Bad OG zu → Plan Morgen 22,0 °C", causeKind: .heating),
        LogEntry(date: t("07:10"), roomID: "schlafzimmer", radiatorID: nil, kind: .write, action: "Modus Aus (Active = 0), 2 Heizkörper", reason: "fenster", detail: "Fenster Schlafzimmer 10 s offen", causeKind: .window),
        LogEntry(date: t("07:30"), roomID: "schlafzimmer", radiatorID: nil, kind: .write, action: "Modus Heizen, Soll 20,5 / 20,0 °C", reason: "fensterZu", detail: "Fenster Schlafzimmer zu → Plan Morgen 20,0 °C", causeKind: .heating),
        LogEntry(date: t("09:00"), roomID: "bad-og", radiatorID: "bad-1", kind: .write, action: "Soll 19,0 °C", reason: "plan", detail: "Tag 19,0 °C + Offset 0", causeKind: .planSetback),
        LogEntry(date: t("12:10"), roomID: "kueche", radiatorID: "kueche-1", kind: .write, action: "Modus Aus (Active = 0)", reason: "fenster", detail: "Fenster Küche 10 s offen", causeKind: .window),
        LogEntry(date: t("12:25"), roomID: "kueche", radiatorID: "kueche-1", kind: .write, action: "Modus Heizen, Soll 21,0 °C", reason: "fensterZu", detail: "Fenster Küche zu → Plan Tag 21,0 °C", causeKind: .heating),
        LogEntry(date: t("14:10"), roomID: "bad-og", radiatorID: "bad-1", kind: .observation, action: "Ventil 10 % → 0 %", reason: nil, detail: "Aus der History abgeleitet", causeKind: .valveClosed),
        LogEntry(date: t("17:00"), roomID: "bad-og", radiatorID: "bad-1", kind: .write, action: "Soll 22,0 °C", reason: "plan", detail: "Abend 22,0 °C + Offset 0", causeKind: .heating),
        LogEntry(date: t("19:30"), roomID: "kaminzimmer", radiatorID: "kamin-fenster", kind: .write, action: "Modus Aus (Active = 0)", reason: "kamin", detail: "Schalter „Kamin an“; Heizung Tür nicht auf der Kamin-Liste", causeKind: .fireplace),
        LogEntry(date: t("21:20"), roomID: "esszimmer", radiatorID: nil, kind: .push, action: "Push „Raumsensor Esszimmer ausgefallen“", reason: nil, detail: "Kein Wert seit 18:20 (> 3 h)", causeKind: .sensorFailure),
        LogEntry(date: t("22:00"), roomID: "kueche", radiatorID: "kueche-1", kind: .write, action: "Soll 18,0 °C", reason: "plan", detail: "Nacht 18,0 °C + Offset 0", causeKind: .planSetback),
        LogEntry(date: t("22:00"), roomID: "esszimmer", radiatorID: "ess-1", kind: .write, action: "Soll 19,0 °C", reason: "plan", detail: "Nacht 18,0 °C + Offset +1,0 °C", causeKind: .planSetback),
        LogEntry(date: t("22:00"), roomID: "schlafzimmer", radiatorID: "schlaf-links", kind: .write, action: "Soll 16,5 °C", reason: "plan", detail: "Nacht 16,0 °C + Offset +0,5 °C", causeKind: .planSetback),
        LogEntry(date: t("22:00"), roomID: "schlafzimmer", radiatorID: "schlaf-rechts", kind: .write, action: "Soll 16,0 °C", reason: "plan", detail: "Nacht 16,0 °C + Offset 0", causeKind: .planSetback),
        LogEntry(date: t("22:10"), roomID: "schlafzimmer", radiatorID: "schlaf-rechts", kind: .observation, action: "Soll 16,0 → 19,0 °C", reason: nil, detail: "Ohne Schreibzugriff des Servers: manuelle Änderung", causeKind: .manual),
        LogEntry(date: t("22:25"), roomID: "kueche", radiatorID: "kueche-1", kind: .write, action: "Modus Aus (Active = 0)", reason: "fenster", detail: "Fenster Küche 10 s offen", causeKind: .window),
    ].sorted { $0.date > $1.date }

    static func log(for radiator: Radiator) -> [LogEntry] {
        log.filter { $0.radiatorID == radiator.id || ($0.radiatorID == nil && $0.roomID == radiator.roomID) }
    }
}
