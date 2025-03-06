# Setup FlowKit Adapter

The `FlowKit Adapter` app must run in foreground to be able to subscribe to HomeKit events.
To ensure that the app will always run, you could use a Mac or an iPhone/iPad.

## Setup on Mac

The following setup will install a `launchctl` daemon that ensure, that the app will restart and kept in foreground.

* Save the following file at `~/Library/LaunchAgents/de.juliankahnert.HomeAutomation.plist`:
```
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>Label</key>
    <string>Restart HomeAutomation after it has crashed</string>
     <key>ProgramArguments</key>
      <array>
         <string>open</string>
         <string>/Applications/FlowKit Adapter.app</string>
      </array>
</dict>
</plist>
```

* Register the plist file in LaunchD `launchctl load ~/Library/LaunchAgents/de.juliankahnert.HomeAutomation.plist`

## Setup on iOS/iPadOS

Start the app and keep it in foreground.
You might want to use [iOS: Guided Access](https://support.apple.com/en-us/111795) to ensure it keeps running.

## Logging

```
log stream --process "HomeAutomation" --level info --predicate 'subsystem == "SmartHomeAutomation"' > testing.log

log collect --predicate 'subsystem == "SmartHomeAutomation"' --output ~/mylogs.logarchive
```
