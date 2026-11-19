# Glossary

Domain language of HomeAutomation's heating control. German UI terms in parentheses.

**Room** (Raum)
A place (`PlaceId`) whose radiators are controlled together. Radiators, window contacts and sensors of a room are named explicitly in its configuration. One heating automation owns one room and is the only writer of that room's radiator targets.
_Avoid_: zone, area

**Radiator** (Heizkörper)
One thermostat valve device, e.g. an Eve Thermo. A room has one or more.

**Plan** (Plan, Zeitplan)
The schedule of a room: switch points per weekday group. Lives in the configuration, not at runtime.

**Switch point** (Schaltpunkt)
A time of day with a target temperature in a plan. The server writes only at switch points and on events.

**Plan target** (Plan-Soll)
The target temperature the plan defines for a room at a moment, without any calibration offset of a radiator.

**Actual** (Ist)
The room's temperature: the room sensor if the room has one, otherwise the mean of its radiators' own measurements. Its source is always shown.

**Δ (delta)**
Actual minus plan target. The comfort band is ±0.5 K.

**Off** (aus)
A radiator that is not heating, written as `Active = 0`; frost and valve protection stay with the thermostat itself.

**Window-off** (Fenster-aus)
All radiators of a room are off while any of its window contacts has been open for the configured delay; when the last one closes, the room returns to its plan target at once.

**Fireplace mode** (Kamin-Modus)
The configured radiators are off while the fireplace is on. The fireplace counts like an open window contact. It ends automatically after eight hours, with a push notification.

**Reason** (Grund)
Why the server wrote a radiator target: `plan`, `window`, `fireplace` or `system`. Stored with each write in the action log.

**Observed change** (beobachtet)
A radiator's target differs from the value the server wrote last. Derived for display; the server does not react to it.
