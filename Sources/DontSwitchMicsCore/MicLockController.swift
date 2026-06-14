import Foundation

public enum EnforcementReason: String, Equatable {
    case startup
    case defaultChanged
    case devicesChanged
    case serviceRestarted
    case wake
    case manual
    case cli
}

public enum EnforcementResult: Equatable {
    case locked(AudioDeviceSnapshot)
    case alreadyLocked(AudioDeviceSnapshot)
    case disabled
    case needsSelection
    case targetMissing(savedName: String?)
    case failed(String)

    public var userVisibleText: String {
        switch self {
        case let .locked(device):
            return "Restored \(device.name)"
        case let .alreadyLocked(device):
            return "Default input is \(device.name)"
        case .disabled:
            return "Lock disabled"
        case .needsSelection:
            return "Choose a microphone"
        case let .targetMissing(savedName):
            if let savedName, !savedName.isEmpty {
                return "Waiting for \(savedName)"
            }
            return "Waiting for selected microphone"
        case let .failed(message):
            return message
        }
    }
}

public protocol AudioDeviceManaging: AnyObject {
    func devices() throws -> [AudioDeviceSnapshot]
    func inputDevices() throws -> [AudioDeviceSnapshot]
    func currentDefaultInputDevice() throws -> AudioDeviceSnapshot
    func device(uid: String) throws -> AudioDeviceSnapshot
    @discardableResult func setDefaultInputDevice(uid: String) throws -> AudioDeviceSnapshot
    func startListening(queue: DispatchQueue, handler: @escaping (CoreAudioDeviceEvent) -> Void) throws
    func stopListening() throws
}

extension CoreAudioDeviceClient: AudioDeviceManaging {}

public struct MicLockSettingsStore {
    public static let suiteName = "com.tombonness.dontswitchmics"

    public enum Key {
        public static let preferredInputDeviceUID = "preferredInputDeviceUID"
        public static let preferredInputDeviceName = "preferredInputDeviceName"
        public static let lockEnabled = "lockEnabled"
        public static let didAttemptInitialLoginRegistration = "didAttemptInitialLoginRegistration"
    }

    public let defaults: UserDefaults

    public init(defaults: UserDefaults = MicLockSettingsStore.makeDefaultSuite()) {
        self.defaults = defaults
    }

    public static func makeDefaultSuite() -> UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    public var preferredInputDeviceUID: String? {
        get { nonEmptyString(forKey: Key.preferredInputDeviceUID) }
        nonmutating set { defaults.set(newValue, forKey: Key.preferredInputDeviceUID) }
    }

    public var preferredInputDeviceName: String? {
        get { nonEmptyString(forKey: Key.preferredInputDeviceName) }
        nonmutating set { defaults.set(newValue, forKey: Key.preferredInputDeviceName) }
    }

    public var lockEnabled: Bool {
        get {
            guard defaults.object(forKey: Key.lockEnabled) != nil else {
                return true
            }
            return defaults.bool(forKey: Key.lockEnabled)
        }
        nonmutating set { defaults.set(newValue, forKey: Key.lockEnabled) }
    }

    public var didAttemptInitialLoginRegistration: Bool {
        get {
            guard defaults.object(forKey: Key.didAttemptInitialLoginRegistration) != nil else {
                return false
            }
            return defaults.bool(forKey: Key.didAttemptInitialLoginRegistration)
        }
        nonmutating set { defaults.set(newValue, forKey: Key.didAttemptInitialLoginRegistration) }
    }

    public func savePreferredInputDevice(_ device: AudioDeviceSnapshot) {
        defaults.set(device.uid, forKey: Key.preferredInputDeviceUID)
        defaults.set(device.name, forKey: Key.preferredInputDeviceName)
    }

    private func nonEmptyString(forKey key: String) -> String? {
        guard let value = defaults.string(forKey: key), !value.isEmpty else {
            return nil
        }
        return value
    }
}

public struct MicLockPolicyState: Equatable {
    public let lockEnabled: Bool
    public let preferredInputDeviceUID: String?
    public let preferredInputDeviceName: String?

    public init(lockEnabled: Bool, preferredInputDeviceUID: String?, preferredInputDeviceName: String?) {
        self.lockEnabled = lockEnabled
        self.preferredInputDeviceUID = preferredInputDeviceUID
        self.preferredInputDeviceName = preferredInputDeviceName
    }

    public var disabledResult: EnforcementResult? {
        lockEnabled ? nil : .disabled
    }
}

public final class MicLockController: @unchecked Sendable {
    public typealias ResultHandler = (EnforcementReason, EnforcementResult) -> Void

    private let deviceClient: AudioDeviceManaging
    private var settings: MicLockSettingsStore
    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Void>()
    private let resultHandler: ResultHandler?
    private var pendingDebounceWorkItem: DispatchWorkItem?
    private var pendingDebounceReason: EnforcementReason?

    public init(
        deviceClient: AudioDeviceManaging = CoreAudioDeviceClient(),
        settings: MicLockSettingsStore = MicLockSettingsStore(),
        queue: DispatchQueue = DispatchQueue(label: "com.tombonness.dontswitchmics.controller"),
        resultHandler: ResultHandler? = nil
    ) {
        self.deviceClient = deviceClient
        self.settings = settings
        self.queue = queue
        self.resultHandler = resultHandler
        self.queue.setSpecific(key: queueKey, value: ())
    }

    public var policyState: MicLockPolicyState {
        queue.syncIfNeeded(key: queueKey) {
            MicLockPolicyState(
                lockEnabled: settings.lockEnabled,
                preferredInputDeviceUID: settings.preferredInputDeviceUID,
                preferredInputDeviceName: settings.preferredInputDeviceName
            )
        }
    }

    public var lockEnabled: Bool {
        get { queue.syncIfNeeded(key: queueKey) { settings.lockEnabled } }
        set { queue.syncIfNeeded(key: queueKey) { settings.lockEnabled = newValue } }
    }

    public var preferredInputDeviceUID: String? {
        queue.syncIfNeeded(key: queueKey) { settings.preferredInputDeviceUID }
    }

    public var preferredInputDeviceName: String? {
        queue.syncIfNeeded(key: queueKey) { settings.preferredInputDeviceName }
    }

    public func allDevices() throws -> [AudioDeviceSnapshot] {
        try queue.syncIfNeeded(key: queueKey) { try deviceClient.devices() }
    }

    public func inputDevices() throws -> [AudioDeviceSnapshot] {
        try queue.syncIfNeeded(key: queueKey) { try eligibleInputDevices() }
    }

    public func currentDefaultInputDevice() throws -> AudioDeviceSnapshot {
        try queue.syncIfNeeded(key: queueKey) { try deviceClient.currentDefaultInputDevice() }
    }

    @discardableResult
    public func selectPreferredDevice(uid: String) throws -> AudioDeviceSnapshot {
        try queue.syncIfNeeded(key: queueKey) {
            let device = try deviceClient.device(uid: uid)
            guard device.inputChannelCount > 0, device.canBeDefaultInput else {
                throw CoreAudioDeviceError.notInputDefaultCapable(name: device.name)
            }
            settings.savePreferredInputDevice(device)
            return device
        }
    }

    @discardableResult
    public func selectPreferredDevice(name: String) throws -> AudioDeviceSnapshot {
        try queue.syncIfNeeded(key: queueKey) {
            let matches = try eligibleInputDevices().filter { $0.name == name }
            guard let device = matches.first else {
                throw CoreAudioDeviceError.deviceNotFound(uid: name)
            }
            guard matches.count == 1 else {
                throw CoreAudioDeviceError.deviceNameNotUnique(name: name)
            }
            settings.savePreferredInputDevice(device)
            return device
        }
    }

    @discardableResult
    public func setDefaultInputDevice(uid: String) throws -> AudioDeviceSnapshot {
        try queue.syncIfNeeded(key: queueKey) {
            try deviceClient.setDefaultInputDevice(uid: uid)
        }
    }

    public func startAutomaticEnforcement() throws {
        try queue.syncIfNeeded(key: queueKey) {
            try deviceClient.startListening(queue: queue) { [weak self] event in
                self?.scheduleDebouncedEnforcement(reason: event.enforcementReason)
            }
        }
    }

    public func stopAutomaticEnforcement() throws {
        try queue.syncIfNeeded(key: queueKey) {
            pendingDebounceWorkItem?.cancel()
            pendingDebounceWorkItem = nil
            pendingDebounceReason = nil
            try deviceClient.stopListening()
        }
    }

    @discardableResult
    public func enforce(reason: EnforcementReason) -> EnforcementResult {
        queue.syncIfNeeded(key: queueKey) {
            let result = enforceOnQueue(reason: reason)
            resultHandler?(reason, result)
            return result
        }
    }

    private func scheduleDebouncedEnforcement(reason: EnforcementReason) {
        queue.asyncIfNeeded(key: queueKey) { [weak self] in
            guard let self else { return }
            self.pendingDebounceReason = reason
            guard self.pendingDebounceWorkItem == nil else {
                return
            }
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let reason = self.pendingDebounceReason ?? reason
                self.pendingDebounceReason = nil
                self.pendingDebounceWorkItem = nil
                let result = self.enforceOnQueue(reason: reason)
                self.resultHandler?(reason, result)
            }
            self.pendingDebounceWorkItem = workItem
            self.queue.asyncAfter(deadline: .now() + .milliseconds(250), execute: workItem)
        }
    }

    private func enforceOnQueue(reason: EnforcementReason) -> EnforcementResult {
        let state = MicLockPolicyState(
            lockEnabled: settings.lockEnabled,
            preferredInputDeviceUID: settings.preferredInputDeviceUID,
            preferredInputDeviceName: settings.preferredInputDeviceName
        )
        if let disabledResult = state.disabledResult {
            return disabledResult
        }

        let target: AudioDeviceSnapshot
        do {
            target = try resolveTargetDevice(state: state)
        } catch {
            return enforcementResult(for: error, state: state)
        }

        guard target.inputChannelCount > 0, target.canBeDefaultInput else {
            return .failed("\(target.name) is not available as a default input device")
        }
        if target.isDefaultInput {
            return .alreadyLocked(target)
        }

        do {
            try deviceClient.setDefaultInputDevice(uid: target.uid)
            Thread.sleep(forTimeInterval: 0.25)
            let currentDefault = try deviceClient.currentDefaultInputDevice()
            if currentDefault.uid == target.uid {
                return .locked(currentDefault)
            }
            return .failed("Default input is still \(currentDefault.name) (\(currentDefault.uid)); expected \(target.name) (\(target.uid))")
        } catch let error as CoreAudioDeviceError {
            return enforcementResult(for: error, state: state)
        } catch {
            return .failed(String(describing: error))
        }
    }

    private func resolveTargetDevice(state: MicLockPolicyState) throws -> AudioDeviceSnapshot {
        if let savedUID = state.preferredInputDeviceUID {
            return try deviceClient.device(uid: savedUID)
        }

        let devices = try deviceClient.devices()
        guard let selectedDevice = DeviceAutoSelector.selectPreferredDevice(from: devices) else {
            throw TargetResolutionError.needsSelection
        }
        settings.savePreferredInputDevice(selectedDevice)
        return selectedDevice
    }

    private func enforcementResult(for error: Error, state: MicLockPolicyState) -> EnforcementResult {
        if error is TargetResolutionError {
            return .needsSelection
        }
        if case CoreAudioDeviceError.deviceNotFound = error, state.preferredInputDeviceUID != nil {
            return .targetMissing(savedName: state.preferredInputDeviceName)
        }
        if let coreAudioError = error as? CoreAudioDeviceError {
            return .failed(coreAudioError.description)
        }
        return .failed(String(describing: error))
    }

    private func eligibleInputDevices() throws -> [AudioDeviceSnapshot] {
        try deviceClient.devices()
            .filter { $0.inputChannelCount > 0 && $0.canBeDefaultInput }
            .sorted { lhs, rhs in
                let leftName = lhs.name.lowercased()
                let rightName = rhs.name.lowercased()
                if leftName != rightName {
                    return leftName < rightName
                }
                return lhs.uid.lowercased() < rhs.uid.lowercased()
            }
    }
}

private enum TargetResolutionError: Error {
    case needsSelection
}

private extension CoreAudioDeviceEvent {
    var enforcementReason: EnforcementReason {
        switch self {
        case .defaultInputChanged:
            return .defaultChanged
        case .devicesChanged:
            return .devicesChanged
        case .serviceRestarted:
            return .serviceRestarted
        }
    }
}

private extension DispatchQueue {
    func syncIfNeeded<T>(key: DispatchSpecificKey<Void>, execute work: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: key) != nil {
            return try work()
        }
        return try sync(execute: work)
    }

    func asyncIfNeeded(key: DispatchSpecificKey<Void>, execute work: @escaping () -> Void) {
        if DispatchQueue.getSpecific(key: key) != nil {
            work()
        } else {
            async(execute: work)
        }
    }
}
