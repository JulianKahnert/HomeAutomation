# Glossary

Domain language of HomeAutomation's heating control. German UI terms in parentheses.

**Report** (Meldung)
One state of one entity as a source sends it to the server (`HomeEvent.change`). A source may report as often as it wants, also a value it reported before; the server alone decides whether a report is a change. A report whose values differ from the entity's current state, or the first report of an entity the server has never seen, is a change: it is stored and reaches the automations.
_Avoid_: event (for a single report), update

**Replay** (Wiederholung)
A report whose values equal the entity's current state; only its timestamp differs. A replay is no change, however long ago the last change was: it is not stored and triggers no automation. It still counts as a sign of life for HomeKit and is still checked against the last command, so a command the device did not take can be sent again. The server holds the current state of every entity in memory for as long as the process lives.

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
A sensor of a room that switches radiators off while it is open: a window contact or the fireplace mode (`RoomContact.window`, `RoomContact.fireplace`). A room names its contacts explicitly; an unreachable contact counts as closed. A window affects every radiator of the room; the fireplace affects the radiators listed with it (`.fireplace(radiators: [...])`), all of them when it lists none. Precedence is per radiator: a radiator is off while any contact that affects it is open, whatever the cause. It goes off when the first such contact has reached its own delay (the window delay for a window, counted from that contact's last state change so a restart does not restart it; none for the fireplace) and returns to its plan target at once when the last one closes, but only if the server switched it off: the room's own last write to the radiator is an off write, whichever contact's reason it carries (a duplicate off is not recorded, so after a handover between two contacts it can carry the earlier one's). An off write that failed and still waits for its retry counts as switched off too: a contact that closes before the retry went through writes the plan, and that command replaces the queued off. A contact that closes within the delay, or one the adapter re-sends as closed after a restart, writes nothing, however old its stored open row is. The off write carries the reason of the contact that took the radiator off (`window` or `fireplace`); the return to the plan carries the reason of the contact that just closed. A switch point or deploy while a contact is open leaves the radiators it affects off and records the new plan target for them without sending it (see plan history).

**Plan history** (Planverlauf)
The plan line of the room detail follows the stored states of the room's plan target entity (a server-owned entity). At a switch point while a radiator is off nothing is sent to it, but the server still reports the new plan target, so the plan line and Δ follow the plan. That report is no state of the radiator: it is no event, no observed change and not the "last write" that decides whether the radiator returns to the plan.

**Fireplace mode** (Kamin-Modus)
The configured radiators are off while the fireplace is on: every radiator of a room that lists the fireplace as a contact, or only the radiators listed with it. The fireplace mode is a server-owned entity (`Fireplace.stateId`); no HomeKit entity stands behind it. It counts like an open window contact, but without the window delay. Only rooms that list it as a contact follow it, and they react at once: every change of the entity reaches them as a `HomeEvent.change`. It is switched only from the FlowKit Controller app, the Heizung tab (toolbar button) and the push action "Kamin an?", never from Siri, the Home app or a HomeKit scene. The app switches it through `PUT /entities/state`; the new state holds at once, and `GET /heating/fireplace` says whether it is on, since when and when it ends. A repeated "on" does not restart the two hours.

**Fireplace reminder** (Kamin-Erinnerung)
The push "Kamin an? Heizkörper ausschalten" (`FireplaceReminder`), sent when the temperature of the fireplace room's sensor has risen by the *rise* (default 1,0 K) within the *window* (default 30 minutes), measured against the lowest reading in the window. It is not sent while the fireplace is on, and not again within the *minimum interval* (default 2 hours, counted from the last reminder of this server process). It carries the fireplace category, whose action switches the fireplace on; the server never switches it by itself.

**Fireplace state** (Kamin-Zustand)
The state of the server-owned fireplace entity; a fireplace never switched is off. It does not depend on HomeKit: a degraded HomeKit (`HomeKitHealth.degraded`) stops the radiator writes, which are retried, not the fire, so the state stays what the owner switched. A switch the database could not save still holds in the server process, so an end stays an end. The history of the former Homebridge switch `Keller_Kamin_switcher` was carried over once; its old rows stay, but nothing reads them for the fireplace. The two-hour end bounds the damage of a fireplace left on.

**Fireplace end** (Kamin-Ende)
Two hours (`Fireplace.maxDuration`) after the fireplace went on the `FireplaceTimeout` automation ends it by setting the server's state, and sends the push "Kamin aus". The two hours are measured from the stored switch-on time, so a restart does not restart them. The push goes out only from the run that switched it off, so once per time the fireplace was on.

**Restart and deploy** (Neustart und Deploy)
On a server start each room re-applies only its overrides (a window open, the fireplace on) from the stored contact states and the stored fireplace state, without waiting for the adapter to re-send them, and writes no plan target: manual values survive. After a configuration deploy each room writes its current plan target once (reason `system`).

**Reason** (Grund)
Why the server wrote a radiator target: `plan`, `window`, `fireplace` or `system`. Stored with each write in the action log.

**Observed change** (beobachtet)
A radiator's target differs from the value the server wrote last. Derived for display; the server does not react to it.

**Heating write** (Heizungs-Schreibvorgang)
One command of the server to a radiator, a row of the journal with its reason (`plan`, `window`, `fireplace` or `system`) and the written value. The events of the Heizung tab are built from these rows; the plan target comes from the plan target entity's history. Written by `HomeManager` for every executed radiator command that runs inside a `HeatingWriteContext`; kept for good (the rows are small, and SQL queries over the long term are the point), no cleanup job deletes them.

**Global configuration** (globale Konfiguration)
The values every room shares unless it overrides them: the standard plan and the window delay. Built once in the configuration repository and handed to each room automation.

**Server start / config deploy** (Serverstart / Konfigurations-Deploy)
Two separate events for automations (`HomeEvent.serverStarted`, `.configDeployed`). A server start writes nothing to the radiators, so manual changes at a radiator survive it; it sets up again what the adapter's resync no longer triggers, because a replay is no change: an open window is registered with the opening time of its stored state, and motion still held in the dark switches the light on. A deploy makes every room write its current plan target once, with reason `system`.


**Time grid** (Zeitraster)
The samples of a room detail: one every 5 minutes (30 minutes for 7 days), ending now. Each sample holds the last stored value at or before its time, because values are only stored when they change. Actual value and valves are `null` when the last reading is older than the sensor failure limit (6 hours unless configured otherwise) or when there is none yet.

**Gap** (Lücke)
Two meanings, kept apart. In the data: a stretch of the time grid without an actual value; lines are not drawn across it. In the chart: the area between the actual line and the plan line, coloured by Δ (blue too cold, grey in the comfort band, orange too warm).

**Room detail** (Raumdetail)
What `GET /heating/rooms/{placeId}?range=2h|24h|7d` answers and the Heizung tab draws for one room: actual, plan target, Δ and one valve percentage per radiator on the time grid. The plan target comes from the stored states of the room's plan target entity and falls back to the room's plan before the first state in the range.

**Overview** (Übersicht)
The first view of the Heizung tab: one Δ bar per room, coldest first, rooms without an actual value last. Per room the server answers actual, plan target, Δ and the source of the actual value (`GET /heating/overview`); the room's name and axis label come from the optional `displayName` and `shortLabel` of its `RoomHeating` (place id and a label derived from the name without them); sorting is derived in the Controller, and bars and selection are matched by place id, never by label. The bars run on a fixed scale of ±3 K; a bar beyond it runs off the end of the plot instead of rescaling it.

**Heatmap cell** (Heatmap-Zelle)
One cell of the week heatmap: the mean Δ of one room over one six-hour segment (0–6, 6–12, 12–18, 18–24 o'clock) of a local day in Europe/Berlin, computed from the 30-minute grid of the room detail. A cell is `null` (hatched in the app) when more than half of the samples of its segment have no actual value (exactly half still counts). Days and segments follow the local clock, so a day with 23 or 25 hours has shorter or longer segments. The overview endpoint carries the cells of the last seven local days, today included; the current segment counts only the samples up to now.

**Week heatmap** (Wochen-Heatmap)
The card "Woche" of the Heizung tab: rooms × days × four segments as rounded cells, coloured like the bars (blue too cold, grey in the comfort band, orange too warm, deeper tint for a larger Δ), hatched without actual value. The value appears only on tap or hover; there is no legend.

**Heating event** (Ereignis)
Something that happened in a room, in the room detail's `events` (`source`, title, reason, real `start`, optional `end`, `pin`): `plan` (a plan switch, from the plan writes), `window` and `fireplace` (from the contact's history, for the fireplace the history of its entity, with a duration; a window counts only when the server wrote for it, the fireplace that ran the full two hours says the timeout ended it), `observed` and `system` (see observed change and heating write reason). An event that began before the range keeps its real start and its `pin` sits at the range start; events outside the range are dropped. Several radiators written within a minute are one event.

**Pin** (Pin)
The small SF Symbol above the room detail's chart for one event: `calendar` plan, `window.vertical.open` window, `flame` fireplace, `hand.raised` observed, `gearshape` system. At most two rows; a pin that finds both rows taken joins the last pin of the second row as a "+n" pin that lists all of them. Plan pins show up to 24 h only. Tapping or hovering shows the reason, as a popover on Mac and iPad and as an inline card on iPhone. Window and fireplace events with a duration also draw an area over the plot. There is no legend.

## Server core

Terms of the server core after the levers. Entries describe the target form; they are in force once the ticket that builds them is done.

**Deadline** (Frist)
A value kind with three cases: none, running until a moment, overdue. One stored row holds it: the number for the end, the text for the case.

**Fensterschließzeit**
The end of a window's deadline: the moment by which an open window has to be closed. Once it has passed, the deadline is overdue (überschritten).

**Projection** (Projektion)
An automation without own state and without waiting: it reads entities and hands a computed result over as a delivery. For a projection events are worked through in order, none is replaced or collapsed, so no alert is lost. The window projection computes the Live Activity content.

**Delivery** (Zustellung)
A push the server hands to the notification adapter, which executes deliveries in the order they were handed over and knows no feature. Automations reach it through one method at the `HomeManager`, not through `perform`.

**Value kind** (Werttyp)
The kind of value a state carries: Bool, number or text, with one descriptor per kind that names unit, display and storage rule. Not the storage policy's `StorageKind`, which only groups characteristic types by retention and rollup rules.

**Origin** (Herkunft)
Where a change came from: `homekit`, `server`, `app`, or the name of a polling job. Only `homekit` counts as a sign of life of HomeKit.

**Report** (Meldung)
Telling the `HomeManager` a new state: an adapter reports what a device says, the server reports what it owns itself. A report is checked and set at once, tells the caller whether it changed, and a repeat changes nothing. It is not a command; the command path stays reserved for devices (ADR-003).

**Server-owned entity** (servereigene Entity)
An entity no device stands behind: the server keeps its state itself and reports it with origin `server` or, when the app sets it, `app`. Examples: the fireplace, a window's deadline, the plan target of a room.

**Polling job** (Abfrage-Job)
A job of the scheduler with a cadence that polls a source (valves, weather, price), feeds the result into the event stream with the job's name as origin and logs an error once per disturbance.

**Polled characteristic** (aktiv gelesene Eigenschaft)
A HomeKit characteristic the adapter reads itself instead of waiting for a notification: battery level, temperature and humidity. It is read on every full resync and every three hours and sent as a normal report with origin `homekit`. The battery is not subscribed, because more subscriptions make HomeKit drop notifications.

**HomeKit inventory** (HomeKit-Bestand)
The list of everything HomeKit has, one row per characteristic, mapped to our model or not, in the table `homekitInventory`. The server pulls it from the adapter after each connect and once a day; it is the query surface for "what does HomeKit have that our automations do not use". Not the same as the entities, which are only the mapped characteristics that reported.

**Lane** (Spur)
The queue of events one automation works through in order. A slow automation delays only its own lane. When several changes of the same entity wait in one lane only the newest stays; events without a state (button press, clock, sun, server start, deploy) are never collapsed.

**Journal** (Journal)
The one record of runs, commands and pushes, one table with an entry per kind. A command entry carries its reason (`plan`, `window`, `fireplace`, `system`).
