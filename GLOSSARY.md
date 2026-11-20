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

**Contact** (Kontakt)
A sensor of a room that switches its radiators off while it is open: the window contacts, and later the fireplace switch. A room names its contacts explicitly (`RoomContact`); an unreachable contact counts as closed. The room goes off when the earliest open contact has been open for the window delay (counted from that contact's last state change, so a restart does not restart the delay) and returns to its plan target at once when the last one closes, but only if it had gone off: a contact that closes within the delay, or re-sent as closed after a restart, writes nothing. The return is recorded with reason `window`; a switch point or deploy while a contact is open leaves the radiators off.

**Fireplace mode** (Kamin-Modus)
The configured radiators are off while the fireplace is on. The fireplace counts like an open window contact. It ends automatically after eight hours, with a push notification.

**Reason** (Grund)
Why the server wrote a radiator target: `plan`, `window`, `fireplace` or `system`. Stored with each write in the action log.

**Observed change** (beobachtet)
A radiator's target differs from the value the server wrote last. Derived for display; the server does not react to it.

**Heating write** (Heizungs-Schreibvorgang)
One write of the server to a radiator, persisted with its reason, the written value and, when the write follows the plan, the plan target. The plan history and the events of the Heizung tab are built from these records; the in-memory action log carries the same reason. Written by `HomeManager` for every executed radiator command that runs inside a `HeatingWriteContext`; kept for 90 days.

**Global configuration** (globale Konfiguration)
The values every room shares unless it overrides them: the standard plan and the window delay. Built once in the configuration repository and handed to each room automation.

**Server start / config deploy** (Serverstart / Konfigurations-Deploy)
Two separate events for automations (`HomeEvent.serverStarted`, `.configDeployed`). A server start re-applies nothing in T1, so manual changes at a radiator survive it; a deploy makes every room write its current plan target once, with reason `system`.

