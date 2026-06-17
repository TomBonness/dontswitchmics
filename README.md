<div align="center">

# Don't Switch Mics

**A tiny macOS menu bar app that keeps your chosen USB/DJI microphone selected.**

[![Swift](https://img.shields.io/badge/Swift-6-orange.svg)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-13%2B-blue.svg)](https://www.apple.com/macos/)
[![CoreAudio](https://img.shields.io/badge/CoreAudio-HAL-lightgrey.svg)](https://developer.apple.com/documentation/coreaudio)
[![Privacy](https://img.shields.io/badge/audio-not%20recorded-brightgreen.svg)](#privacy)

AirPods connected? Zoom got clever? macOS switched inputs again?

**Don't Switch Mics puts your real mic back.**

</div>

---

## What it does

Don't Switch Mics watches the system default input device. When macOS moves the default input away from your saved microphone, it restores the saved device automatically.

Built for the common desk setup:

- A USB receiver like `DJI MIC MINI`
- AirPods that keep stealing input
- A built-in Mac microphone that should stay out of the way
- A menu bar app you can forget about once configured

## Highlights

- **Locks by CoreAudio UID** — not by transient device ID.
- **Auto-picks DJI over AirPods/Built-in** on first launch when unambiguous.
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

```sh
make list
swift run dontswitchmicsctl --select-device-name "DJI MIC MINI"
swift run dontswitchmicsctl --set-default-input-name "MacBook Air Microphone"
swift run dontswitchmicsctl --current-default-input
swift run dontswitchmicsctl --enforce-once
swift run dontswitchmicsctl --current-default-input
```

Expected result:

1. The default input moves to `MacBook Air Microphone`.
2. `--enforce-once` restores `DJI MIC MINI`.
3. The final default input is `DJI MIC MINI`.

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

### `DJI MIC MINI` is not connected

Run:

```sh
swift run dontswitchmicsctl --list-devices
```

If `DJI MIC MINI` is missing, connect the receiver over USB and click `Refresh Devices` in the menu.

Once a preferred UID is saved, Don't Switch Mics will **not** fall back to AirPods or the built-in microphone. It waits for the saved mic to return.

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
