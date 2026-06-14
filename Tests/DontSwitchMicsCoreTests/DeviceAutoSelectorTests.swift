import CoreAudio
@testable import DontSwitchMicsCore
import Foundation
import Testing

@Suite
struct DeviceAutoSelectorTests {
    @Test
    func djiUSBBeatsAirPodsBuiltInAndGenericUSB() {
        let selected = DeviceAutoSelector.selectPreferredDevice(from: [
            device(name: "AirPods Pro", uid: "airpods", manufacturer: "Apple", transportType: kAudioDeviceTransportTypeBluetooth),
            device(name: "MacBook Air Microphone", uid: "built-in", manufacturer: "Apple", transportType: kAudioDeviceTransportTypeBuiltIn),
            device(name: "USB Audio Device", uid: "generic-usb", manufacturer: "Generic", transportType: kAudioDeviceTransportTypeUSB),
            device(name: "DJI MIC MINI", uid: "dji-usb", manufacturer: "DJI Technology Co., Ltd.", transportType: kAudioDeviceTransportTypeUSB)
        ])

        #expect(selected?.uid == "dji-usb")
    }

    @Test
    func anyDJIInputBeatsNonDJIUSBWhenNoDJIUSBExists() {
        let selected = DeviceAutoSelector.selectPreferredDevice(from: [
            device(name: "USB Audio Device", uid: "generic-usb", manufacturer: "Generic", transportType: kAudioDeviceTransportTypeUSB),
            device(name: "Wireless DJI Mic", uid: "dji-bluetooth", manufacturer: "DJI Technology Co., Ltd.", transportType: kAudioDeviceTransportTypeBluetooth)
        ])

        #expect(selected?.uid == "dji-bluetooth")
    }

    @Test
    func singleGenericUSBInputIsSelectedWhenNoDJIDeviceExists() {
        let selected = DeviceAutoSelector.selectPreferredDevice(from: [
            device(name: "AirPods Pro", uid: "airpods", manufacturer: "Apple", transportType: kAudioDeviceTransportTypeBluetooth),
            device(name: "MacBook Air Microphone", uid: "built-in", manufacturer: "Apple", transportType: kAudioDeviceTransportTypeBuiltIn),
            device(name: "USB Audio Device", uid: "generic-usb", manufacturer: "Generic", transportType: kAudioDeviceTransportTypeUSB)
        ])

        #expect(selected?.uid == "generic-usb")
    }

    @Test
    func multipleNonDJIUSBInputsProduceNeedsSelection() {
        let devices = [
            device(name: "USB Audio A", uid: "generic-a", manufacturer: "Generic", transportType: kAudioDeviceTransportTypeUSB),
            device(name: "USB Audio B", uid: "generic-b", manufacturer: "Generic", transportType: kAudioDeviceTransportTypeUSB)
        ]
        #expect(DeviceAutoSelector.selectPreferredDevice(from: devices) == nil)

        let client = RecordingAudioDeviceClient(devices: devices)
        let controller = MicLockController(
            deviceClient: client,
            settings: testSettings(),
            queue: DispatchQueue(label: "DeviceAutoSelectorTests.needsSelection")
        )
        #expect(controller.enforce(reason: .cli) == .needsSelection)
        #expect(client.setDefaultInputUIDs == [])
    }

    @Test
    func savedUIDMissingNeverFallsBackToAnotherDevice() {
        let settings = testSettings()
        settings.preferredInputDeviceUID = "missing-dji"
        settings.preferredInputDeviceName = "DJI MIC MINI"
        let client = RecordingAudioDeviceClient(devices: [
            device(name: "USB Audio Device", uid: "generic-usb", manufacturer: "Generic", transportType: kAudioDeviceTransportTypeUSB)
        ])
        client.missingUIDs.insert("missing-dji")

        let controller = MicLockController(
            deviceClient: client,
            settings: settings,
            queue: DispatchQueue(label: "DeviceAutoSelectorTests.missingSavedUID")
        )

        #expect(controller.enforce(reason: .cli) == .targetMissing(savedName: "DJI MIC MINI"))
        #expect(client.deviceLookupUIDs == ["missing-dji"])
        #expect(client.devicesCallCount == 0)
        #expect(client.setDefaultInputUIDs == [])
        #expect(settings.preferredInputDeviceUID == "missing-dji")
    }

    @Test
    func disabledLockReturnsDisabledWithoutCoreAudioPolicyWork() {
        let state = MicLockPolicyState(
            lockEnabled: false,
            preferredInputDeviceUID: "dji-usb",
            preferredInputDeviceName: "DJI MIC MINI"
        )

        #expect(state.disabledResult == .disabled)
    }
}

private func device(
    name: String,
    uid: String,
    manufacturer: String,
    transportType: UInt32,
    inputChannelCount: UInt32 = 1,
    canBeDefaultInput: Bool = true,
    isDefaultInput: Bool = false
) -> AudioDeviceSnapshot {
    let id = uid.utf8.reduce(UInt32(1)) { partial, byte in
        partial &* 31 &+ UInt32(byte)
    }
    return AudioDeviceSnapshot(
        id: AudioDeviceID(id),
        uid: uid,
        name: name,
        manufacturer: manufacturer,
        transportType: transportType,
        inputChannelCount: inputChannelCount,
        canBeDefaultInput: canBeDefaultInput,
        isDefaultInput: isDefaultInput
    )
}

private func testSettings() -> MicLockSettingsStore {
    let suiteName = "com.tombonness.dontswitchmics.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return MicLockSettingsStore(defaults: defaults)
}

private final class RecordingAudioDeviceClient: AudioDeviceManaging {
    var listedDevices: [AudioDeviceSnapshot]
    var missingUIDs: Set<String> = []
    var devicesCallCount = 0
    var deviceLookupUIDs: [String] = []
    var setDefaultInputUIDs: [String] = []

    init(devices: [AudioDeviceSnapshot]) {
        self.listedDevices = devices
    }

    func devices() throws -> [AudioDeviceSnapshot] {
        devicesCallCount += 1
        return listedDevices
    }

    func inputDevices() throws -> [AudioDeviceSnapshot] {
        try devices().filter { $0.inputChannelCount > 0 }
    }

    func currentDefaultInputDevice() throws -> AudioDeviceSnapshot {
        if let defaultDevice = listedDevices.first(where: \.isDefaultInput) {
            return defaultDevice
        }
        return listedDevices[0]
    }

    func device(uid: String) throws -> AudioDeviceSnapshot {
        deviceLookupUIDs.append(uid)
        if missingUIDs.contains(uid) {
            throw CoreAudioDeviceError.deviceNotFound(uid: uid)
        }
        guard let device = listedDevices.first(where: { $0.uid == uid }) else {
            throw CoreAudioDeviceError.deviceNotFound(uid: uid)
        }
        return device
    }

    func setDefaultInputDevice(uid: String) throws -> AudioDeviceSnapshot {
        setDefaultInputUIDs.append(uid)
        guard let selected = listedDevices.first(where: { $0.uid == uid }) else {
            throw CoreAudioDeviceError.deviceNotFound(uid: uid)
        }
        listedDevices = listedDevices.map { snapshot in
            AudioDeviceSnapshot(
                id: snapshot.id,
                uid: snapshot.uid,
                name: snapshot.name,
                manufacturer: snapshot.manufacturer,
                transportType: snapshot.transportType,
                inputChannelCount: snapshot.inputChannelCount,
                canBeDefaultInput: snapshot.canBeDefaultInput,
                isDefaultInput: snapshot.uid == uid
            )
        }
        return selected
    }

    func startListening(queue: DispatchQueue, handler: @escaping (CoreAudioDeviceEvent) -> Void) throws {}
    func stopListening() throws {}
}
