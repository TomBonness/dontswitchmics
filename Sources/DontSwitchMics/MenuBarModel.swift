import AppKit
import Combine
import DontSwitchMicsCore
import Foundation
import ServiceManagement

@MainActor
final class MenuBarModel: ObservableObject {
    @Published var devices: [AudioDeviceSnapshot] = []
    @Published var selectedUID: String?
    @Published var lockEnabled = true
    @Published var lastResult: EnforcementResult = .needsSelection
    @Published var launchAtLoginStatus: SMAppService.Status = LaunchAtLoginController.status
    @Published var launchAtLoginError: String?

    private var didStart = false
    private var wakeObserver: NSObjectProtocol?
    private var settings = MicLockSettingsStore()

    private lazy var controller = MicLockController { [weak self] _, result in
        Task { @MainActor [weak self] in
            self?.lastResult = result
            self?.syncStateFromController()
            self?.refreshDevicesOnly()
        }
    }

    var selectedDeviceName: String? {
        settings.preferredInputDeviceName
    }

    var launchAtLoginEnabled: Bool {
        launchAtLoginStatus == .enabled || LaunchAtLoginController.fallbackLaunchAgentInstalled
    }

    var launchAtLoginRequiresApproval: Bool {
        launchAtLoginStatus == .requiresApproval
    }

    init() {
        start()
    }


    func start() {
        guard !didStart else { return }
        didStart = true
        syncStateFromController()
        refreshDevicesOnly()
        attemptInitialLoginRegistrationIfNeeded()
        do {
            try controller.startAutomaticEnforcement()
        } catch {
            lastResult = .failed(String(describing: error))
        }
        lastResult = controller.enforce(reason: .startup)
        syncStateFromController()
        refreshDevicesOnly()
        refreshLaunchAtLoginStatus()
        installWakeObserver()
    }

    func setLockEnabled(_ enabled: Bool) {
        controller.lockEnabled = enabled
        syncStateFromController()
        if enabled {
            lastResult = controller.enforce(reason: .manual)
            refreshDevicesOnly()
        } else {
            lastResult = .disabled
        }
    }

    func selectDevice(_ device: AudioDeviceSnapshot) {
        do {
            try controller.selectPreferredDevice(uid: device.uid)
            syncStateFromController()
            lastResult = controller.enforce(reason: .manual)
            refreshDevicesOnly()
        } catch {
            lastResult = .failed(String(describing: error))
        }
    }

    func refreshDevicesAndEnforce() {
        refreshDevicesOnly()
        lastResult = controller.enforce(reason: .manual)
        syncStateFromController()
        refreshDevicesOnly()
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        do {
            try LaunchAtLoginController.setEnabled(enabled)
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = String(describing: error)
        }
        refreshLaunchAtLoginStatus()
    }

    func approveLaunchAtLoginInSystemSettings() {
        LaunchAtLoginController.openSystemSettingsLoginItems()
        refreshLaunchAtLoginStatus()
    }

    private func attemptInitialLoginRegistrationIfNeeded() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        guard settings.didAttemptInitialLoginRegistration == false else { return }
        do {
            try LaunchAtLoginController.setEnabled(true)
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = String(describing: error)
        }
        settings.didAttemptInitialLoginRegistration = true
        refreshLaunchAtLoginStatus()
    }

    private func installWakeObserver() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.lastResult = self.controller.enforce(reason: .wake)
                self.syncStateFromController()
                self.refreshDevicesOnly()
            }
        }
    }

    private func syncStateFromController() {
        selectedUID = controller.preferredInputDeviceUID
        lockEnabled = controller.lockEnabled
    }

    private func refreshDevicesOnly() {
        do {
            devices = try controller.inputDevices()
        } catch {
            devices = []
            lastResult = .failed(String(describing: error))
        }
    }

    private func refreshLaunchAtLoginStatus() {
        launchAtLoginStatus = LaunchAtLoginController.status
    }
}
