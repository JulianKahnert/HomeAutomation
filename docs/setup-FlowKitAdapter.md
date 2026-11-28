# Setup FlowKit Adapter

The `FlowKit Adapter` app has to keep running to receive HomeKit events.
Use a Mac (recommended) or an iPhone/iPad.

On iOS/iPadOS HomeKit only delivers events while the app is in the foreground.
On a Mac (Mac Catalyst) the app only has to run: it keeps receiving HomeKit events while hidden, while another app is in front and while the screen is locked.

## Setup on Mac

A LaunchAgent starts the app hidden at login and restarts it whenever it crashes or quits.
`open -g -j` starts it in the background and hidden, `-W` keeps `open` running until the app quits, so launchd only restarts it after the app has ended.

* Save the following file at `~/Library/LaunchAgents/de.juliankahnert.HomeAutomation.adapter.plist`:
```
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>de.juliankahnert.HomeAutomation.adapter</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-g</string>
        <string>-W</string>
        <string>-j</string>
        <string>/Applications/FlowKit Adapter.app</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
```

* Quit a running `FlowKit Adapter` first, otherwise two adapters connect and keep replacing each other's connection.
* Load the agent: `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/de.juliankahnert.HomeAutomation.adapter.plist`
* Restart the adapter, also via ssh: `pkill -x "FlowKit Adapter"`. launchd starts it again, hidden. (`launchctl kickstart -k` only restarts `open`, not the app.)
* Enable automatic login, so the agent runs after the Mac restarts.

Pitfalls:

* Plain `open` without `-W` exits right away, so `KeepAlive` reruns it every 10 seconds and every run brings the app to the front and takes the focus.
* Do not put the app binary (`…/Contents/MacOS/FlowKit Adapter`) into `ProgramArguments`. Started that way, the Catalyst app logs "starting" and then hangs: it never connects to the server or HomeKit. It has to be launched through LaunchServices, i.e. `open`.

## Server connection

Open the settings screen (gear icon) in the app and enter host, port and the server's `AUTH_TOKEN`.

* The token is stored in the keychain. Installs that still have it in `UserDefaults` from older versions are migrated automatically on first launch and the plaintext copy is deleted.
* Enable **Use TLS (wss://)** whenever the adapter does not share a trusted network with the server (e.g. when connecting through the Cloudflare tunnel). Without TLS the token and all HomeKit traffic cross the network unencrypted.

## Reading values actively

The adapter subscribes to HomeKit notifications only for the types that matter (`CharacteristicsType.isSubscribed`), because too many subscriptions make HomeKit drop notifications, contact sensors first. Battery level, temperature and humidity (`isPolled`) are additionally read actively: on every full resync (start, reconnect) and every three hours (`CharacteristicsType.pollInterval`). The values go to the server as normal reports; the server stores a value only when it changed (the battery by at least one percentage point), see `ValueDescriptor.StorageRule`.

## Setup on iOS/iPadOS

Start the app and keep it in foreground.
You might want to use [iOS: Guided Access](https://support.apple.com/en-us/111795) to ensure it keeps running.

## Logging

The adapter writes one JSON object per line to daily files in
`~/Library/Containers/de.juliankahnert.HomeKitAdapterApp/Data/Documents/logs/` (on macOS) and to the unified log.
It logs at `info`; debug logs (e.g. every thermostat value update and read) are off by default. Turn them on with any of:

* the **Debug Logs** toggle in the settings screen,
* `defaults write de.juliankahnert.HomeKitAdapterApp HA_DEBUG_LOGGING -bool YES` (macOS; `-bool NO` or `defaults delete de.juliankahnert.HomeKitAdapterApp HA_DEBUG_LOGGING` turns them off),
* the environment variable `HA_DEBUG_LOGGING=1`, which also overrides the other two (`HA_DEBUG_LOGGING=0` forces them off).

The setting is read at launch, so restart the app after changing it.

At every entity refresh the adapter logs each characteristic once (`Characteristic found`) with its service and
characteristic type UUIDs (`serviceType`, `characteristicType`) and the stored entity type. Use it to identify
characteristics HomeKit only calls "Custom". `dropped: true` marks a characteristic without an entity id, which never
reaches the server. Most are expected (firmware version, name, ...) and stay at `info`; one of a thermostat or one with a
known entity type is logged at `notice`, because its history silently stays empty.


```
log stream --process "HomeAutomation" --level info --predicate 'subsystem == "SmartHomeAutomation"' > testing.log

log collect --predicate 'subsystem == "SmartHomeAutomation"' --output ~/mylogs.logarchive
```
