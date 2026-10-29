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

## Setup on iOS/iPadOS

Start the app and keep it in foreground.
You might want to use [iOS: Guided Access](https://support.apple.com/en-us/111795) to ensure it keeps running.

## Logging

```
log stream --process "HomeAutomation" --level info --predicate 'subsystem == "SmartHomeAutomation"' > testing.log

log collect --predicate 'subsystem == "SmartHomeAutomation"' --output ~/mylogs.logarchive
```
