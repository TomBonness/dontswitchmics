# Don't Switch Mics

macOS likes to move the default input back to AirPods, a built-in microphone, or another transient device. Don't Switch Mics keeps a chosen USB/DJI microphone selected as the system default input and restores it when the default changes.

The app only enumerates CoreAudio devices and changes the default input. It does not capture, meter, or record audio.

## Install

```sh
make install
```

The installer packages the app, copies it to `/Applications/DontSwitchMics.app` when possible, falls back to `$HOME/Applications/DontSwitchMics.app`, and opens it.

## Menu usage

Use the mic icon in the menu bar.

- `Locked to: <mic>` shows the saved microphone.
- `Keep selected microphone active` enables or disables enforcement.
- Choose a microphone from the device list to save it and immediately restore it as the default input.
- `Refresh Devices` reloads CoreAudio devices and enforces once.
- `Launch at Login` registers the app for login. If macOS requires approval, choose `Approve in System Settings…`.
- `Quit Don't Switch Mics` stops the menu bar app.

## CLI verification

```sh
make list
swift run dontswitchmicsctl --select-device-name "DJI MIC MINI"
swift run dontswitchmicsctl --set-default-input-name "MacBook Air Microphone"
swift run dontswitchmicsctl --current-default-input
swift run dontswitchmicsctl --enforce-once
swift run dontswitchmicsctl --current-default-input
```

Expected: the default input moves away, `--enforce-once` restores `DJI MIC MINI`, and the final default input is `DJI MIC MINI`.

## Change the locked mic

Open the menu bar item and choose a different input-capable/default-capable device. Or use:

```sh
swift run dontswitchmicsctl --select-device-name "Exact Device Name"
```

The saved device is tracked by CoreAudio UID, not the transient device ID.

## Disable launch at login

Turn off `Launch at Login` in the menu. If macOS still lists the app, remove it from System Settings → General → Login Items.

## Troubleshooting

### `DJI MIC MINI` is not connected

Run:

```sh
swift run dontswitchmicsctl --list-devices
```

If `DJI MIC MINI` is missing, connect the receiver over USB and run `Refresh Devices` from the menu. The app will not fall back to AirPods or the built-in microphone once a preferred UID is saved; it waits for the saved microphone to return.

### The menu says `Choose a microphone`

No preferred UID is saved and auto-selection could not choose unambiguously. Select the mic from the menu or with `--select-device-name`.

### The menu says `Waiting for <mic>`

The saved mic UID is not currently available. Reconnect that mic or choose a new one.
