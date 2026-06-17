import AppKit
import DontSwitchMicsCore
import SwiftUI

@main
struct DontSwitchMicsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = MenuBarModel()

    var body: some Scene {
        MenuBarExtra("Mic", systemImage: "mic") {
            MenuBarContent(model: model)
                .onAppear { model.start() }
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}

private struct MenuBarContent: View {
    @ObservedObject var model: MenuBarModel

    var body: some View {
        Text(headerText)
            .font(.headline)
        Text(model.lastResult.userVisibleText)
        Divider()

        Toggle(
            "Keep selected microphone active",
            isOn: Binding(
                get: { model.lockEnabled },
                set: { model.setLockEnabled($0) }
            )
        )

        Section("Microphones") {
            if model.devices.isEmpty {
                Text("No eligible input devices")
            } else {
                ForEach(model.devices) { device in
                    Button(deviceMenuTitle(for: device)) {
                        model.selectDevice(device)
                    }
                }
            }
        }

        Button("Refresh Devices") {
            model.refreshDevicesAndEnforce()
        }

        Divider()

        Toggle(
            "Launch at Login",
            isOn: Binding(
                get: { model.launchAtLoginEnabled },
                set: { model.setLaunchAtLoginEnabled($0) }
            )
        )
        if model.launchAtLoginRequiresApproval {
            Button("Approve in System Settings…") {
                model.approveLaunchAtLoginInSystemSettings()
            }
        }
        if let launchAtLoginError = model.launchAtLoginError {
            Text(launchAtLoginError)
        }

        Divider()

        Button("Quit Don't Switch Mics") {
            NSApplication.shared.terminate(nil)
        }
    }

    private var headerText: String {
        if let selectedDeviceName = model.selectedDeviceName {
            return "Locked to: \(selectedDeviceName)"
        }
        return "Choose a microphone"
    }

    private func deviceMenuTitle(for device: AudioDeviceSnapshot) -> String {
        let marker = device.uid == model.selectedUID ? "✓ " : ""
        return "\(marker)\(device.name) — \(transportLabel(for: device.transportType))"
    }
}
