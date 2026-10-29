# Research: Adapter (FlowKit Adapter) aus der Ferne neu starten

Stand: 2026-10-29 · Branch `feature/215-file-log-crash` (Commit `90f32a8`)

Frage: Wie lässt sich der FlowKit Adapter, also die iOS-/Mac-Catalyst-App, die HomeKit über den `StarActorSystem`-WebSocket `/adapter/v1` an den Server anbindet, aus der Ferne neu starten oder wieder verbinden?

> **Nachtrag 29.10.2026, auf dem Mac mini getestet:** Unter macOS (Catalyst) liefert HomeKit Events auch, wenn die App versteckt ist, eine andere App vorne ist oder der Bildschirm gesperrt ist (CO₂-Sensor alle 30 s, drei geschaltete Lampen kamen sofort an). Die Vordergrund-Pflicht in §1 gilt nur für iOS. Der direkte Binary-Aufruf aus §3.1 und §5 **funktioniert nicht**: Die Catalyst-App loggt „starting“ und hängt dann ohne Server- und HomeKit-Verbindung. Sie muss über LaunchServices starten. Auf dem Mac mini läuft jetzt `open -g -W -j` mit `KeepAlive`: Start versteckt und ohne Fokus, launchd startet erst nach dem App-Ende neu. Fern-Neustart per `ssh … pkill -x "FlowKit Adapter"`, nicht per `kickstart -k`. Getestet mit `kill`: Die App war nach ~5 s wieder verbunden. Die Anleitung steht in `docs/setup-FlowKitAdapter.md`.

Quellen sind nur Primärquellen: Apple-Entwicklerdoku, Apple Support / Platform Deployment, Man-Pages von macOS (`man 5 launchd.plist`, `man 1 launchctl`, `man 1 open`) und der Code dieses Repos. Repo-Zitate stehen als `Pfad:Zeile`. Aussagen, die keine Primärquelle belegt, sind als **unbelegt** markiert.

---

## 1. Ausgangslage im Repo

- **HomeKit braucht die App im Vordergrund.** Das Repo schreibt das selbst (`docs/setup-FlowKitAdapter.md:3`), und Apple bestätigt es: „HomeKit APIs can only be used when your application is in the foreground.“ ([WWDC14 Session 213 „Introducing HomeKit“](https://nonstrict.eu/wwdcindex/wwdc2014/213/)). Ein Apple-DTS-Engineer schreibt: „HomeKit background access isn't supported“, dafür sei auch nie ein Entitlement vergeben worden ([Apple Developer Forums, Thread 850391](https://developer.apple.com/forums/thread/850391)). Für macOS vermutet derselbe Engineer, dass HomeKit eine laufende App unabhängig vom Hintergrundstatus als „foreground“ behandelt. Das ist ausdrücklich nicht getestet (ebd.).
- **Die App ist eine iOS-App mit Mac-Catalyst-Build** (`SUPPORTS_MACCATALYST = YES`, `Apps/FlowKitAdapter/FlowKit Adapter.xcodeproj/project.pbxproj:317`). Auf dem Mac läuft also dieselbe App als Catalyst.
- **Das Wiederverbinden passiert schon heute im Prozess.** `URLSessionWebSocketTransport` hat eine Reconnect-Schleife mit exponentiellem Backoff von 1 s bis 30 s und versucht es endlos (`Sources/StarActorSystem/URLSessionWebSocketTransport.swift:14-16`, `:64-72`). Dazu kommen ein Handshake-Watchdog mit 10 s (`:25`, `:97-118`) und ein Ping-Keepalive (`:120-131`). Laut ADR erholen sich iOS-Installationen damit „in-process (no restart mechanism required)“ (`docs/adr-001-replace-distributedcluster-with-staractorsystem.md:44`). Den Neustart per launchctl als Recovery-Mittel hat das ADR ausdrücklich gestrichen (`:55`).
- **Nach jedem Handshake schickt der Adapter den kompletten HomeKit-Zustand** (`Sources/Adapter/AdapterConnection.swift:89-94`).
- **Den HomeKit-Teil setzt die App selbst zurück.** Alle 6 h erzeugt sie `HMHomeManager` neu, weil HomeKit-Delegates nach einigen Stunden ausbleiben können (`Sources/Adapter/HomeKitAdapter+Delegates.swift:45-56`).
- **Die Connection hängt an einem SwiftUI-`.task`.** Ändern sich Adresse oder Token, ruft die App `stop()` auf und baut die Connection neu (`Apps/FlowKitAdapter/FlowKitAdapterApp.swift:62-83`, `Sources/Adapter/AdapterConnection.swift:111-117`).
- **Der Server erkennt ein fehlendes Adapter-`.up` nur passiv.** `/health` liefert dann 503 (`Sources/Server/routes.swift:25-50`), und `HomeManager` bekommt den Adapter-Proxy nur, solange die Verbindung `.up` ist (`Sources/Server/configure.swift:243-245`).
- **Achtung, `RestartSystem` heißt nur so:** Die Automation ruft `exit(1)` auf (`Sources/HAImplementations/Automations/RestartSystem.swift:26-29`), läuft aber im `AutomationService` des **Servers** (`Sources/Server/configure.swift:253`). Sie beendet also den Server-Container, nicht den Adapter.
- **Die Mac-Anleitung startet die App über `open` und `KeepAlive=true`** (`docs/setup-FlowKitAdapter.md:12-30`). `open` endet sofort, nachdem es die App gestartet hat. Weil `KeepAlive=true` launchd sagt, den Job „continuously running“ zu halten, und schnell endende Jobs „throttled“ werden (`man 5 launchd.plist`, *KeepAlive*), führt launchd `open` laut Default-Throttle etwa alle 10 s erneut aus (`man 5 launchd.plist`, *ThrottleInterval*: „jobs will not be spawned more than once every 10 seconds“). Ohne `-g` holt `open` die App dabei jedes Mal nach vorn (`man 1 open`, `-g`: „Do not bring the application to the foreground.“). launchd überwacht damit **nicht** den App-Prozess selbst, sondern nur den kurzlebigen `open`-Aufruf. In der Praxis wirkt das trotzdem: Die App wird spätestens ~10 s nach ihrem Ende wieder geöffnet. `launchctl kickstart -k` kann sie so aber nicht gezielt beenden (siehe §3).

---

## 2. iOS

### 2.1 Kann die App sich selbst neu starten? Nein.

- Für iOS gibt es keine API zum Beenden: „There is no API provided for gracefully terminating an iOS application.“ `exit` sieht für den Nutzer wie ein Absturz aus, und `applicationWillTerminate:` läuft dann nicht ([Apple Technical Q&A QA1561](https://developer.apple.com/library/archive/qa/qa1561/_index.html)).
- Eine API, mit der eine iOS-App sich nach dem eigenen Ende wieder in den Vordergrund holt, gibt es nicht. In keiner der gelesenen Quellen findet sich ein entsprechender Mechanismus. Ein „Crash and relaunch“ funktioniert auf iOS also nur, wenn **etwas außerhalb der App** sie wieder öffnet (Single App Mode, siehe 2.3).
- Folgerung: Auf iOS heißt „neu starten“ im Normalfall **die App-internen Zustände zurücksetzen**, nicht den Prozess neu starten (siehe §4).

### 2.2 Guided Access (geführter Zugriff)

- Guided Access beschränkt das Gerät vorübergehend auf eine App („temporarily restrict your device to a single app“). Man kann Auto-Lock und Zeitlimit einstellen, und zum Beenden braucht es Code, Face ID oder Touch ID ([Apple Support 111795](https://support.apple.com/en-us/111795)).
- Was nach einem App-Absturz oder Geräteneustart passiert, sagt die Seite nicht (ebd.). Dass Guided Access eine abgestürzte App neu startet, ist **unbelegt**.
- Guided Access hat keine Fernsteuerung. Es hält die App nur im Vordergrund.

### 2.3 Single App Mode / App Lock (supervised, Apple Configurator oder MDM)

- Das App-Lock-Payload `com.apple.app.lock` „locks to the specified app until removal of the profile. The device returns to the app automatically upon wake or restart.“ Es setzt auf iOS ein **supervised** Gerät voraus, lässt sich unter iOS aber auch manuell installieren ([DeviceManagement › AppLock](https://developer.apple.com/documentation/devicemanagement/applock)).
- In Apple Configurator heißt es: „Single App Mode forces the selected app to open on the supervised device … the app reopens immediately after the device is restarted.“ Gestartet wird über *Actions › Advanced › Start Single App Mode* ([Apple Configurator User Guide: Single App Mode](https://support.apple.com/guide/apple-configurator-mac/cadbf9c172/mac)).
- Zu den Optionen gehört `DisableAutoLock`: „the device doesn't automatically go to sleep after an idle period“ ([AppLock.App.Options](https://developer.apple.com/documentation/devicemanagement/applock/app-data.dictionary/options-data.dictionary)).
- Dass App Lock eine **abgestürzte** App sofort neu öffnet (also auch nach `exit()`), sagt keine der gelesenen Quellen ausdrücklich. Die Doku nennt nur „wake or restart“. Das ist **unbelegt**, wäre aber der einzige Weg, auf dem `exit()` auf iOS als Neustart taugt. Vor dem Einsatz einmal auf dem Zielgerät testen.

### 2.4 MDM-Befehle

- **`RestartDevice`** startet das Gerät „remotely and immediately“ neu. Der Befehl braucht unter iOS, macOS und tvOS Supervision und das Access Right `AllowPasscodeRemovalAndLock`. Wichtig: „A passcode-locked iOS device doesn't rejoin a Wi-Fi network after restarting, so it may not be able to communicate with the server.“ ([DeviceManagement › Restart Device](https://developer.apple.com/documentation/devicemanagement/restart-device-command)).
- Mit App Lock zusammen ergibt das **Gerät neu starten → App öffnet sich automatisch wieder** (siehe 2.3). Das ist der einzige dokumentierte, wirklich ferngesteuerte „Kaltstart“ der App auf iOS. Voraussetzung: Das Gerät hat **keinen Code**, sonst bleibt es ohne WLAN (siehe oben).
- Einen MDM-Befehl „App neu starten“ oder „App beenden“ nennt die Apple-Doku für DeviceManagement in den gelesenen Seiten nicht. Ob das Entfernen und Neuinstallieren des App-Lock-Profils per MDM die App neu startet, ist **unbelegt**.

### 2.5 Kurzbefehle: persönliche Automationen

- Persönliche Automationen haben Auslöser wie „time of day, arrival at a location, or the opening of an app“ ([Shortcuts User Guide: Intro to personal automation](https://support.apple.com/en-ca/guide/shortcuts/apd690170742/9.0/ios/26)).
- Laut Apple dürfen diese Auslöser **ohne Rückfrage** laufen, unter anderem „Time of Day … Wi-Fi … App … Battery Level, Charger“. Dafür *Privacy › Allow Running When Locked* aktivieren. Dann gilt: „The automation will not notify you when it's triggered.“ ([Shortcuts User Guide: Add automations](https://support.apple.com/guide/shortcuts/apdfbdbd7123/ios)).
- Einsatz: zum Beispiel täglich um 04:00 die Aktion „App öffnen → FlowKit Adapter“ als Absicherung, falls die App im Hintergrund gelandet ist. Damit lässt sich die App **in den Vordergrund holen, aber nicht neu starten**. Wie sich das mit App Lock oder Guided Access verträgt, ist **unbelegt**. Die Kurzbefehle-App kann der Server nicht direkt auslösen.

### 2.6 Silent Push / Background Push

- Eine Hintergrund-Mitteilung „wakes your app in the background“. Das System liefert sie mit niedriger Priorität und ohne Garantie aus: „doesn't guarantee their delivery … don't try to send more than two or three per hour“. Pro Mitteilung bleiben 30 s. Wird die App beendet, verwirft das System die zurückgehaltene Mitteilung ([Pushing background updates to your App](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app)).
- Der Adapter hat zwar `UIBackgroundModes = remote-notification` und `aps-environment` (`Apps/FlowKitAdapter/Info.plist:7-10`, `Apps/FlowKitAdapter/FlowKitAdapter.entitlements`), registriert sich aber nirgends für Pushes. `registerForRemoteNotifications` gibt es nur im Controller (`Sources/Controller/Dependencies/PushNotificationDependency.swift:47`).
- Bewertung: Ein Push weckt die App höchstens **im Hintergrund**. HomeKit funktioniert dort nicht (§1), und die App kommt dadurch nicht in den Vordergrund. Ein Push kann also keinen Neustart auslösen, höchstens einen Reconnect-Versuch des WebSockets für 30 s.

### 2.7 BGTaskScheduler

- `BGTaskScheduler` plant Arbeit, die läuft, „even when the app is suspended“. `BGAppRefreshTask` ist für kurze Aktualisierungen „while the app is in the background“ gedacht ([BGTaskScheduler](https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler), [BGAppRefreshTask](https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtask)).
- Bewertung: Läuft nur im Hintergrund, also ohne HomeKit, und das System bestimmt den Zeitpunkt. Zum Neustarten ungeeignet.

### 2.8 Display und Sleep

- `isIdleTimerDisabled = true` verhindert, dass das Gerät in den Ruhezustand geht. Apple empfiehlt das nur, wenn es nötig ist ([UIApplication.isIdleTimerDisabled](https://developer.apple.com/documentation/uikit/uiapplication/isidletimerdisabled)). Der Adapter setzt es derzeit nicht. Im Repo gibt es keinen Treffer für `isIdleTimerDisabled`. Unter App Lock übernimmt `DisableAutoLock` diese Aufgabe (siehe 2.3).

---

## 3. macOS (Mac Catalyst)

### 3.1 launchd LaunchAgent mit KeepAlive

- `KeepAlive=true` hält einen Job „continuously running“. Schnell endende Jobs werden gedrosselt, und `KeepAlive` setzt `RunAtLoad` voraus. Mit `KeepAlive.SuccessfulExit=false` startet launchd den Job nur nach einem Ende mit Status ≠ 0 neu (`man 5 launchd.plist`, *KeepAlive*, *SuccessfulExit*). Standard-Throttle: 10 s (*ThrottleInterval*).
- `~/Library/LaunchAgents` enthält „Per-user agents provided by the user“ (`man 8 launchd`, *FILES*). Solche Agents laufen in der GUI-Session des Nutzers. Mit `LimitLoadToSessionType` lässt sich das auf einen Sessiontyp wie `Aqua` beschränken (`man 5 launchd.plist`). Bei einem Mac ohne Monitor muss deshalb ein Nutzer angemeldet sein (automatische Anmeldung). Das folgt aus dem Agent-Modell, ein Test unter Headless-Bedingungen ist **unbelegt**.
- **Besser als die heutige `open`-Variante** (§1): `ProgramArguments` direkt auf `/Applications/FlowKit Adapter.app/Contents/MacOS/FlowKit Adapter` setzen. Dann überwacht launchd den echten App-Prozess, startet ihn nach einem Absturz oder `exit` neu und kann ihn mit `kickstart -k` gezielt beenden. Ob eine Catalyst-App, die so per execv gestartet wird, wie gewohnt in den Vordergrund kommt, ist **unbelegt** und muss getestet werden.

### 3.2 `launchctl kickstart` per SSH

- `launchctl kickstart -k <service-target>`: „If the service is already running, kill the running instance before restarting the service.“ Das Ziel für einen Nutzer-Agent ist `gui/<uid>/<label>` (`man 1 launchctl`, *kickstart*, *gui/<uid>*). Alternativ `launchctl kill SIGTERM gui/<uid>/<label>` (*kill*).
- Per SSH als derselbe Nutzer: `launchctl kickstart -k gui/$(id -u)/de.juliankahnert.HomeAutomation`.
- Das wirkt nur, wenn launchd den App-Prozess selbst verwaltet (siehe 3.1). Bei der heutigen `open`-Variante würde `kickstart -k` nur `open` neu starten, eine laufende App bliebe unberührt.
- Hinweis: Das `Label` in der aktuellen Anleitung ist ein Satz („Restart HomeAutomation after it has crashed“, `docs/setup-FlowKitAdapter.md:20-21`). Für `gui/<uid>/<label>` sollte es ein Reverse-DNS-Label sein, das zum Dateinamen passt.

### 3.3 Anmeldeobjekte / SMAppService

- `SMAppService` gibt es ab macOS 13 und Mac Catalyst 16. Damit registriert eine App Login Items, LaunchAgents und LaunchDaemons. Für LaunchAgents ersetzt es das Ablegen von Plists in `~/Library/LaunchAgents` ([SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)).
- `SMAppService.mainApp` „configure[s] the main app to launch at login“ ([mainApp](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp)). Laut `register()` gilt für die Haupt-App nur „launches on subsequent logins“. Einen **Neustart nach Absturz** gibt es nur für LoginItem-Helper-Bundles („If the helper crashes or exits with a non-zero status, the system relaunches it“) ([register()](https://developer.apple.com/documentation/servicemanagement/smappservice/register())).
- `SMAppService.agent(plistName:)` lädt eine Plist aus `Contents/Library/LaunchAgents` im App-Bundle ([agent(plistName:)](https://developer.apple.com/documentation/servicemanagement/smappservice/agent(plistname:))). Dort ist `BundleProgram` erlaubt, also ein Pfad relativ zum Bundle („only supported for plists that are installed using SMAppService“, `man 5 launchd.plist`). So käme der KeepAlive-Agent mit der App mit und müsste nicht von Hand installiert werden.

### 3.4 MDM auf dem Mac

- `RestartDevice` gibt es auch für macOS (supervised) ([Restart Device](https://developer.apple.com/documentation/devicemanagement/restart-device-command)). Das ist allerdings viel zu grob, solange SSH und launchd verfügbar sind.

---

## 4. Auslöser vom Server über den bestehenden WebSocket

### 4.1 Was technisch schon da ist

- Der Server hält einen Proxy auf `HomeKitCommandReceiver` unter der fest vergebenen ID `.homeKitCommandReceiver` (`Sources/Server/configure.swift:230`, `Sources/StarActorSystem/StarActorID.swift:24`). Der Adapter registriert den Actor in `AdapterConnection.init` (`Sources/Adapter/AdapterConnection.swift:64-66`).
- Ein neuer Befehl ist eine zusätzliche `distributed func` auf `HomeKitCommandReceiver` (`Sources/Adapter/DistributedActors/HomeKitCommandReceiver.swift:18-62`). Laut ADR ist das „one compiler-checked `distributed func`“ (`docs/adr-001-…md:43`).
- Rahmenbedingungen:
  - Die gemangelten Thunk-IDs gehören zum Wire-Format, Golden-Tests fixieren sie (`docs/adr-001-…md:49`, `Tests/StarActorSystemTests/GoldenThunkIDTests.swift`).
  - Änderungen am Protokoll müssen additiv sein (`docs/adr-001-…md:50`).
  - Ein Adapter mit älterem Build kennt die neue Methode nicht, der Aufruf schlägt dann fehl. `protocolVersion` bleibt bei 1 (`Sources/StarActorSystem/StarActorSystem.swift:27`).
  - Aufrufe scheitern sofort, wenn die Verbindung nicht `.up` ist (`StarActorSystem.swift:118-125`), und haben ein Timeout (`:137`).

### 4.2 Skizze `restart(mode:)`

```swift
// HomeKitCommandReceiver (Adapter-Modul, wird auch vom Server als Proxy genutzt)
public distributed func requestRestart(_ mode: AdapterRestartMode) async {
    log.notice("requestRestart(\(mode)) — received remote call")
    // erst antworten, dann asynchron handeln: sonst reißt der Teardown
    // die eigene Reply-Verbindung ab und der Server sieht ein Timeout
    Task { try? await Task.sleep(for: .milliseconds(500)); await onRestart(mode) }
}

public enum AdapterRestartMode: String, Codable, Sendable {
    case resetHomeKit      // HMHomeManager neu erzeugen (wie der 6h-Timer) + pushFullState
    case reconnect         // AdapterConnection.stop() + neu bauen (wie bei Adress-/Token-Wechsel)
    case terminateProcess  // exit(…) – nur sinnvoll, wenn etwas den Prozess neu startet
}
```

- `onRestart` reicht die App beim Erzeugen des Receivers als Closure herein (heute `AdapterConnection.swift:64-66`). So bleibt der Receiver frei von App-Logik.
- `.reconnect` kann dasselbe tun wie der `.task(id:)`-Pfad in `FlowKitAdapterApp.swift:62-83`, also `stop()` und eine neue `AdapterConnection` bauen. Das erzeugt auch `HomeKitAdapter` und damit `HMHomeManager` neu (`AdapterConnection.swift:48-50`).
- Auf dem Server: eine authentifizierte Route, zum Beispiel `POST /adapter/restart`, in `openapi.yaml` plus `OpenAPIController`, die `adapterProxy.requestRestart(...)` aufruft. Optional zusätzlich ein Button im Controller.

### 4.3 Was das kann und was nicht

| Fall | iOS | macOS |
|---|---|---|
| WebSocket `.up`, HomeKit hängt (Delegates bleiben aus, vgl. `HomeKitAdapter+Delegates.swift:45`) | `.resetHomeKit` / `.reconnect` helfen | dito |
| WebSocket `.up`, App-Zustand kaputt | `.reconnect`. `.terminateProcess` nur mit App Lock **und** nur wenn App Lock nach einem Absturz neu öffnet (**unbelegt**, §2.3) | `.terminateProcess` + launchd `KeepAlive` (§3.1) |
| WebSocket **down** | Server kann **nichts** schicken. Das Wiederverbinden übernimmt die Transport-Schleife selbst (`URLSessionWebSocketTransport.swift:64-72`). Sonst bleibt nur MDM `RestartDevice` + App Lock | SSH + `launchctl kickstart -k` |
| App im Hintergrund oder angehalten (iOS) | WebSocket-Aufruf kommt nicht an. Background Push weckt nur ohne HomeKit (§2.6) | n/a |
| Gerät aus oder abgestürzt | MDM `RestartDevice` (nur wenn erreichbar), sonst vor Ort | SSH / Wake-on-LAN, sonst vor Ort |

Kernpunkt: Ein Neustart über den WebSocket greift **nur, solange die Verbindung steht**. Er hilft also gegen „Verbindung steht, aber HomeKit oder App-Zustand hängt“, nicht gegen „Adapter ist weg“. Gegen den zweiten Fall helfen nur Mechanismen außerhalb der App: launchd auf dem Mac, App Lock mit MDM-Restart auf iOS.

---

## 5. Empfehlung

### Immer laufendes iPhone/iPad

1. Das Gerät mit Apple Configurator **supervisen** und **App Lock** (Single App Mode) für FlowKit Adapter mit `DisableAutoLock` einrichten. So öffnet sich die App nach jedem Neustart oder Aufwachen automatisch ([AppLock](https://developer.apple.com/documentation/devicemanagement/applock), [Configurator](https://support.apple.com/guide/apple-configurator-mac/cadbf9c172/mac)).
2. **Keinen Gerätecode** setzen, das Gerät ans Ladegerät und ins WLAN hängen. Sonst bleibt das Gerät nach `RestartDevice` ohne WLAN ([Restart Device](https://developer.apple.com/documentation/devicemanagement/restart-device-command)).
3. Optional ein MDM einrichten, das das Gerät per `RestartDevice` neu starten kann. Das ist der einzige dokumentierte Fern-Kaltstart der App.
4. In der App einen `requestRestart(.resetHomeKit | .reconnect)` per WebSocket einbauen, mit Server-Route und Controller-Button (§4.2). `.terminateProcess` auf iOS erst nach einem Test auf dem Gerät freigeben (öffnet App Lock die App nach `exit` wieder?).
5. Ohne Supervision bleiben Guided Access und eine Kurzbefehle-Automation „Time of Day → App öffnen“ (*Allow Running When Locked*). Damit kommt die App in den Vordergrund zurück, ein Neustart aus der Ferne ist so aber nicht möglich.

### Mac (Catalyst)

1. Den LaunchAgent so umbauen, dass launchd den **App-Prozess direkt** startet:
   ```xml
   <key>Label</key><string>de.juliankahnert.HomeAutomation.adapter</string>
   <key>ProgramArguments</key>
   <array><string>/Applications/FlowKit Adapter.app/Contents/MacOS/FlowKit Adapter</string></array>
   <key>KeepAlive</key><true/>
   <key>LimitLoadToSessionType</key><string>Aqua</string>
   ```
   Laden mit `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/de.juliankahnert.HomeAutomation.adapter.plist` (`man 1 launchctl`). Dass die App so im Vordergrund startet und HomeKit liefert, einmal prüfen. Falls nicht, bleibt die bisherige `open`-Variante, die wie in §1 beschrieben funktioniert.
2. Neustart aus der Ferne: `ssh mac 'launchctl kickstart -k gui/$(id -u)/de.juliankahnert.HomeAutomation.adapter'` (`man 1 launchctl`, *kickstart -k*).
3. Automatische Anmeldung des Nutzers aktivieren, damit der Agent nach einem Mac-Neustart in der GUI-Session läuft (`man 8 launchd`, *FILES*).
4. Optional später einen in der App gebündelten Agent über `SMAppService.agent(plistName:)` mit `BundleProgram` statt einer Plist von Hand ([SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)).
5. Derselbe WebSocket-`requestRestart`. Auf dem Mac ist `.terminateProcess` sicher, weil launchd `KeepAlive` die App neu startet.
