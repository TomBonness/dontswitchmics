import CoreAudio
import Foundation

public enum DeviceAutoSelector {
    public static func selectPreferredDevice(from devices: [AudioDeviceSnapshot]) -> AudioDeviceSnapshot? {
        let eligibleDevices = devices.filter { $0.inputChannelCount > 0 && $0.canBeDefaultInput }
        let djiUSBDevices = sorted(eligibleDevices.filter { isUSB($0) && containsDJI($0) })
        if let selected = djiUSBDevices.first {
            return selected
        }

        let djiDevices = sorted(eligibleDevices.filter(containsDJI))
        if let selected = djiDevices.first {
            return selected
        }

        let usbDevices = sorted(eligibleDevices.filter(isUSB))
        return usbDevices.count == 1 ? usbDevices[0] : nil
    }

    public static func containsDJI(_ device: AudioDeviceSnapshot) -> Bool {
        device.name.localizedCaseInsensitiveContains("DJI")
            || device.manufacturer.localizedCaseInsensitiveContains("DJI")
    }

    public static func isUSB(_ device: AudioDeviceSnapshot) -> Bool {
        device.transportType == kAudioDeviceTransportTypeUSB
    }

    private static func sorted(_ devices: [AudioDeviceSnapshot]) -> [AudioDeviceSnapshot] {
        devices.sorted { lhs, rhs in
            let leftName = lhs.name.lowercased()
            let rightName = rhs.name.lowercased()
            if leftName != rightName {
                return leftName < rightName
            }
            return lhs.uid.lowercased() < rhs.uid.lowercased()
        }
    }
}
