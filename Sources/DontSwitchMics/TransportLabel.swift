import CoreAudio
import Foundation

func transportLabel(for transportType: UInt32) -> String {
    switch transportType {
    case kAudioDeviceTransportTypeUSB:
        return "USB"
    case kAudioDeviceTransportTypeBluetooth:
        return "Bluetooth"
    case kAudioDeviceTransportTypeBuiltIn:
        return "Built-in"
    default:
        return fourCharacterCode(transportType)
    }
}

private func fourCharacterCode(_ code: UInt32) -> String {
    let bytes = [
        UInt8((code >> 24) & 0xff),
        UInt8((code >> 16) & 0xff),
        UInt8((code >> 8) & 0xff),
        UInt8(code & 0xff)
    ]
    let renderedBytes = bytes.map { byte in
        (32...126).contains(byte) ? byte : UInt8(ascii: ".")
    }
    return String(bytes: renderedBytes, encoding: .ascii) ?? "????"
}
