<div align="center">

# Don't Switch Mics

**A tiny macOS menu bar app that keeps your chosen microphone selected.**

[![Swift](https://img.shields.io/badge/Swift-6-orange.svg)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-13%2B-blue.svg)](https://www.apple.com/macos/)
[![CoreAudio](https://img.shields.io/badge/CoreAudio-HAL-lightgrey.svg)](https://developer.apple.com/documentation/coreaudio)
[![Privacy](https://img.shields.io/badge/audio-not%20recorded-brightgreen.svg)](#privacy)

Bluetooth headset connected? Conferencing app got clever? macOS switched inputs again?

**Don't Switch Mics puts your selected mic back.**

</div>

---

## What it does

Don't Switch Mics watches the system default input device. When macOS moves the default input away from the microphone you picked, it restores that saved device automatically.

The rule is simple:

> The mic you choose is the right mic.

Built for any setup where macOS keeps guessing wrong:

- USB microphones
- Audio interfaces
- Wireless receivers
- Built-in mics you only want sometimes
- Bluetooth headsets that should not steal input

## Highlights

- **User-selected first** — once you choose a mic, the app only restores that saved device.
- **Locks by CoreAudio UID** — not by transient device ID.
- **Safe first launch** — auto-selects only when there is one obvious eligible mic; otherwise it asks you to choose.
- **No fallback after selection** — if your saved mic is unplugged, it waits for that mic instead of choosing the wrong one.
- **Fast restore path** — short listener debounce plus immediate readback polling after a restore.
- **Menu bar only** — no Dock icon.
- **Launch at login** — uses `SMAppService` on macOS 13+.
- **CLI included** — deterministic listing, selection, simulation, and one-shot enforcement.

## Privacy

Don't Switch Mics does **not** capture, meter, stream, or record audio.

It only uses CoreAudio HAL APIs to:

1. List audio devices.
2. Read the current default input.
3. Set the default input back to your saved mic.

No microphone permission prompt is expected for this first implementation.

## Install

```sh
make install
```

The installer builds and packages the app, copies it to `/Applications/DontSwitchMics.app` when possible, falls back to `$HOME/Applications/DontSwitchMics.app`, and opens it.

## Use the menu bar app

Click the mic icon in the menu bar.

- `Locked to: <mic>` shows the saved microphone.
- `Keep selected microphone active` enables or disables enforcement.
- Choose any listed microphone to save it and restore it immediately.
- `Refresh Devices` reloads CoreAudio devices and enforces once.
- `Launch at Login` registers the app for login.
- `Approve in System Settings…` appears if macOS requires login-item approval.
- `Quit Don't Switch Mics` stops the app.

## Verify from the CLI

List available inputs:

```sh
make list
```

Select the mic you want to keep active:

```sh
swift run dontswitchmicsctl --select-device-name "Your Microphone Name"
```

Simulate macOS switching away, then restore it:

```sh
swift run dontswitchmicsctl --set-default-input-name "Another Input Name"
swift run dontswitchmicsctl --current-default-input
swift run dontswitchmicsctl --enforce-once
swift run dontswitchmicsctl --current-default-input
```

Expected result:

1. The default input moves to the other input.
2. `--enforce-once` restores your saved microphone.
3. The final default input is your saved microphone.

## Change the locked mic

Use the menu bar device list, or run:

```sh
swift run dontswitchmicsctl --select-device-name "Exact Device Name"
```

The saved device is persisted in `UserDefaults(suiteName: "com.tombonness.dontswitchmics")` under its CoreAudio UID.

## Disable launch at login

Turn off `Launch at Login` in the menu.

If macOS still lists the app, remove it from:

`System Settings → General → Login Items`

## Troubleshooting

### My preferred mic is not connected

Run:

```sh
swift run dontswitchmicsctl --list-devices
```

If the mic is missing, reconnect it and click `Refresh Devices` in the menu.

Once a preferred UID is saved, Don't Switch Mics will **not** fall back to another input. It waits for the saved mic to return.

### The menu says `Choose a microphone`

No preferred UID is saved and auto-selection could not choose safely. Pick the mic from the menu or run `--select-device-name`.

### The menu says `Waiting for <mic>`

The saved mic UID is not currently available. Reconnect that mic or choose a new one.

## Develop

```sh
make build
make test
make package
```

Core files:

- `Sources/DontSwitchMicsCore/CoreAudioDeviceClient.swift` — CoreAudio HAL device access.
- `Sources/DontSwitchMicsCore/MicLockController.swift` — selection, persistence, debounce, and enforcement.
- `Sources/DontSwitchMics/DontSwitchMicsApp.swift` — SwiftUI menu bar app.
- `Sources/dontswitchmicsctl/main.swift` — verification and control CLI.
