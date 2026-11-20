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
A sensor of a room that switches its radiators off while it is open: a window contact or the fireplace switch (`RoomContact.window`, `RoomContact.fireplace`). A room names its contacts explicitly; an unreachable contact counts as closed. Any open contact means off, whatever the cause: the room goes off when the first open contact has reached its own delay (the window delay for a window, counted from that contact's last state change so a restart does not restart it; none for the fireplace) and returns to its plan target at once when the last one closes, but only if it had gone off: a contact that closes within the delay, or re-sent as closed after a restart, writes nothing. If one cause ends while another is still active the radiators stay off. The off write carries the reason of the contact that took the room off (`window` or `fireplace`); the return to the plan carries the reason of the contact that just closed. A switch point or deploy while a contact is open leaves the radiators off.

**Fireplace mode** (Kamin-Modus)
The configured radiators are off while the fireplace is on. The fireplace is the persistent Homebridge switch `Keller_Kamin_switcher` and counts like an open window contact, but without the window delay. Only rooms that list it as a contact follow it. It is switched from the Heizung tab (toolbar button), from the push action "Kamin an?", from Siri or the Home app. The server switches it through `PUT /heating/fireplace`; `GET /heating/fireplace` says whether it is on, since when and when it ends. A repeated "on" does not restart the eight hours.

**Fireplace reminder** (Kamin-Erinnerung)
The push "Kamin an? Heizkörper ausschalten" (`FireplaceReminder`), sent when the temperature of the fireplace room's sensor has risen by the *rise* (default 1,0 K) within the *window* (default 30 minutes), measured against the lowest reading in the window. It is not sent while the fireplace is on, and not again within the *minimum interval* (default 2 hours, counted from the last reminder of this server process). It carries the fireplace category, whose action switches the fireplace on; the server never switches it by itself.

**Unreachable fireplace** (Kamin nicht erreichbar)
A switch whose state the server cannot read counts as off, so the plan keeps running and nothing freezes. The server keeps the last known value when HomeKit cannot be read, so the eight-hour end bounds the damage of a wrongly "on" switch.

**Fireplace end** (Kamin-Ende)
Eight hours after the switch went on the `FireplaceTimeout` automation switches it off and sends a push. The eight hours are measured from the switch-on time stored in the database (the current state of the switch there), not from the cache: after a restart the adapter re-sends every state and the cache then carries the time of that resync.

**Restart and deploy** (Neustart und Deploy)
On a server start each room re-applies only its overrides (a window open, the fireplace on) from the stored contact states, without waiting for the adapter to re-send them, and writes no plan target: manual values survive. After a configuration deploy each room writes its current plan target once (reason `system`).

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


**Time grid** (Zeitraster)
The samples of a room detail: one every 5 minutes (30 minutes for 7 days), ending now. Each sample holds the last stored value at or before its time, because values are only stored when they change. Actual value and valves are `null` when the last reading is older than the sensor failure limit (6 hours unless configured otherwise) or when there is none yet.

**Gap** (Lücke)
Two meanings, kept apart. In the data: a stretch of the time grid without an actual value; lines are not drawn across it. In the chart: the area between the actual line and the plan line, coloured by Δ (blue too cold, grey in the comfort band, orange too warm).

**Room detail** (Raumdetail)
What `GET /heating/rooms/{placeId}?range=2h|24h|7d` answers and the Heizung tab draws for one room: actual, plan target, Δ and one valve percentage per radiator on the time grid. The plan target comes from the plan targets of the heating writes and falls back to the room's plan before the first write in the range.

**Overview** (Übersicht)
The first view of the Heizung tab: a headline and one Δ bar per room, coldest first, rooms without an actual value last. Per room the server answers actual, plan target and the source of the actual value (`GET /heating/overview`); Δ, sorting and headline are derived in the Controller. The bars run on a fixed scale of ±3 K; a bar beyond it runs off the end of the plot instead of rescaling it.

**Headline** (Schlagzeile)
One line above the bars naming the room whose Δ is furthest from zero ("Bad OG am kältesten · 3,7 K unter Plan", "… am wärmsten …"), or "Alle Räume im Plan" when every room is inside the comfort band. Rooms without Δ do not count.

**Heatmap cell** (Heatmap-Zelle)
One cell of the week heatmap: the mean Δ of one room over one six-hour segment (0–6, 6–12, 12–18, 18–24 o'clock) of a local day in Europe/Berlin, computed from the 30-minute grid of the room detail. A cell is `null` (hatched in the app) when more than half of the samples of its segment have no actual value (exactly half still counts). Days and segments follow the local clock, so a day with 23 or 25 hours has shorter or longer segments. The overview endpoint carries the cells of the last seven local days, today included; the current segment counts only the samples up to now.

**Week heatmap** (Wochen-Heatmap)
The card "Woche" of the Heizung tab: rooms × days × four segments as rounded cells, coloured like the bars (blue too cold, grey in the comfort band, orange too warm, deeper tint for a larger Δ), hatched without actual value. The value appears only on tap or hover; there is no legend.

**Heating event** (Ereignis)
Something that happened in a room, in the room detail's `events` (`source`, title, reason, real `start`, optional `end`, `pin`): `plan` (a plan switch, from the plan writes), `window` and `fireplace` (from the contact's history, with a duration; a window counts only when the server wrote for it, the fireplace that ran eight hours says the timeout ended it), `observed` and `system` (see observed change and heating write reason). An event that began before the range keeps its real start and its `pin` sits at the range start; events outside the range are dropped. Several radiators written within a minute are one event.

**Pin** (Pin)
The small SF Symbol above the room detail's chart for one event: `calendar` plan, `window.vertical.open` window, `flame` fireplace, `hand.raised` observed, `gearshape` system. At most two rows; a pin that finds both rows taken joins the last pin of the second row as a "+n" pin that lists all of them. Plan pins show up to 24 h only. Tapping or hovering shows the reason, as a popover on Mac and iPad and as an inline card on iPhone. Window and fireplace events with a duration also draw an area over the plot. There is no legend.
