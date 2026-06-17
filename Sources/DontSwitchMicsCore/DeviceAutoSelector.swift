import CoreAudio
import Foundation

public enum DeviceAutoSelector {
    public static func selectPreferredDevice(from devices: [AudioDeviceSnapshot]) -> AudioDeviceSnapshot? {
        let eligibleDevices = sorted(devices.filter { $0.inputChannelCount > 0 && $0.canBeDefaultInput })
        let usbDevices = eligibleDevices.filter(isUSB)
        if usbDevices.count == 1 {
            return usbDevices[0]
        }
        return eligibleDevices.count == 1 ? eligibleDevices[0] : nil
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
