# HeizungDebugPrototype

Throwaway design prototype for the heating debug views of the FlowKit Controller (heating map,
ticket 06). Mock data only, in memory; nothing here talks to the server or ships. Delete it once
the variant is chosen.

## Brief

- **Surface:** debug views in the FlowKit Controller (iOS, inset-grouped lists, Swift Charts like
  `Sources/Controller/Charts/*` and `EntityHistoryDetailFeature`).
- **Questions every variant must answer:**
  1. „Warum ist Heizkörper X kalt?“ (Fenster offen, Kamin an, Plan-Absenkung, manuelle Änderung,
     Wärmepumpe liefert nicht, Ventil zu, Sensorausfall, Modus Aus)
  2. „Seit wann ist Heizkörper/Raum Y bei Temperatur Z?“
  3. „Ventil seit wann bei wie viel Prozent?“
- **Candidates (Variants menu):**
  - **A Zeitleiste:** one radiator, 24 h; Soll/Eve-Ist/Raum-Ist/Außen overlaid, window/fireplace/
    off bands, server writes as markers; valve chart; state lanes; "seit wann" facts.
  - **B Raumkarten:** whole house now; one card per room with plan, chips, and per radiator the
    one-line "why".
  - **C Entscheidungsprotokoll:** chronological server writes with the `reason` field, plus
    optional derived observations (manual change, valve, sensor push); room filter.
  - **D Diagnose (Hybrid):** one radiator, answer first, checklist of all causes in automation
    order, compact chart, "seit wann", its log slice.
  - **E Skizze v3** (default in the live window): Δ = Ist − Soll bars per room, coldest first,
    comfort band ±0,5 K, room without values hatched with "?"; tap a bar for the lollipop and the
    detail below (Soll dashed step / Ist solid / gap shaded, 2 h / 24 h / 7 T, event pins 📅 🪟 🔥
    ✋ ⚙︎ with popover, duration events as bands, valve step chart sharing x-domain, rules and
    crosshair); week heatmap Δ per room × hour, tap a cell to open room and time. Agreed design
    from `06-prototype--debug-ansichten.md`, section "Zwischenstand Skizze v3".
    Real rooms and thermos: Küche, Esszimmer, Kaminzimmer ("Eve Thermo", Devices.swift), Bad OG
    ("Eve Thermo Bad OG"), Julians Arbeitszimmer ("Eve Thermo Arbeitszimmer", name assumed),
    Schlafzimmer ("Heizung links"); window contacts from Devices.swift. Mock week 08.–15.11.2026:
    Küche "Fenster Links" open, Bad OG valve stuck at 0 %, Arbeitszimmer changed by hand at the
    device, Esszimmer on the fireplace list with "Kamin an", Kaminzimmer thermo silent since
    10.11. (as in reality).
- **Better means:** the question is answered without reading a chart in the common case, and the
  chart is there when the answer is not obvious (valve stuck).
- **Platform:** iOS decides (Controller); judged here at phone width (430 pt) on macOS.
- **Mock scenario (Sun 15.11.2026, 22:40):** Küche window open → Modus Aus; Schlafzimmer night
  setback, right radiator changed by hand; Arbeitszimmer offset +2,0 °C (Eve-Ist ≠ room sensor);
  Kaminzimmer fireplace on, only one radiator on the list; Esszimmer room sensor failed; Bad OG
  valve stuck at 0 % while Soll > Ist. Heat pump state is estimated (not read in v1).

## Run

- `swift run HeizungDebugPrototype`: live macOS window; switch candidates via the **Variants**
  menu (⌘1…⌘5). The radiator picker inside A and D switches scenarios.
- Snapshots: jk:prototyper's `verify-snapshots.sh Apps/HeizungDebugPrototype` renders every
  `#Preview` to `snapshots/`. Needs the GUI session (from SSH it renders nothing).
- iOS: open `Package.swift` in Xcode and use Previews on the Kit target.
