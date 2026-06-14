import CoreAudio
import Foundation

public struct AudioDeviceSnapshot: Identifiable, Equatable, Codable {
    public let id: AudioDeviceID
    public let uid: String
    public let name: String
    public let manufacturer: String
    public let transportType: UInt32
    public let inputChannelCount: UInt32
    public let canBeDefaultInput: Bool
    public let isDefaultInput: Bool

    public init(
        id: AudioDeviceID,
        uid: String,
        name: String,
        manufacturer: String,
        transportType: UInt32,
        inputChannelCount: UInt32,
        canBeDefaultInput: Bool,
        isDefaultInput: Bool
    ) {
        self.id = id
        self.uid = uid
        self.name = name
        self.manufacturer = manufacturer
        self.transportType = transportType
        self.inputChannelCount = inputChannelCount
        self.canBeDefaultInput = canBeDefaultInput
        self.isDefaultInput = isDefaultInput
    }
}

public enum CoreAudioDeviceError: Error, Equatable, CustomStringConvertible {
    case osStatus(operation: String, status: OSStatus)
    case malformedPropertyData(operation: String)
    case deviceNotFound(uid: String)
    case deviceNameNotUnique(name: String)
    case notInputDefaultCapable(name: String)

    public var description: String {
        switch self {
        case let .osStatus(operation, status):
            return "\(operation) failed with OSStatus \(status) (fourCC \(Self.fourCharacterCode(status)), hex \(Self.hexCode(status)))"
        case let .malformedPropertyData(operation):
            return "\(operation) returned malformed CoreAudio property data"
        case let .deviceNotFound(uid):
            return "No current audio device has UID \"\(uid)\""
        case let .deviceNameNotUnique(name):
            return "More than one eligible input device is named \"\(name)\""
        case let .notInputDefaultCapable(name):
            return "\"\(name)\" cannot be used as the default input device"
        }
    }

    public static func fourCharacterCode(_ status: OSStatus) -> String {
        let code = UInt32(bitPattern: status)
        let bytes = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff)
        ]
        let renderedBytes = bytes.map { byte in
            (32...126).contains(byte) ? byte : UInt8(ascii: ".")
        }
        return "'\(String(bytes: renderedBytes, encoding: .ascii) ?? "....")'"
    }

    public static func hexCode(_ status: OSStatus) -> String {
        let code = UInt32(bitPattern: status)
        return "0x" + String(code, radix: 16, uppercase: true).leftPadding(toLength: 8, withPad: "0")
    }
}

public enum CoreAudioDeviceEvent: Equatable {
    case defaultInputChanged
    case devicesChanged
    case serviceRestarted
}

public final class CoreAudioDeviceClient: @unchecked Sendable {
    private struct ListenerRegistration {
        let address: AudioObjectPropertyAddress
        let queue: DispatchQueue
        let block: AudioObjectPropertyListenerBlock
    }

    private let listenerLock = NSLock()
    private var listenerRegistrations: [ListenerRegistration] = []
    private var listenerQueue: DispatchQueue?
    private var listenerHandler: ((CoreAudioDeviceEvent) -> Void)?

    public init() {}

    deinit {
        try? stopListening()
    }

    public func devices() throws -> [AudioDeviceSnapshot] {
        let deviceIDs = try currentDeviceIDs()
        let defaultInputID = try currentDefaultInputDeviceID()
        return try deviceIDs.map { try snapshot(for: $0, defaultInputID: defaultInputID) }
    }

    public func inputDevices() throws -> [AudioDeviceSnapshot] {
        try devices().filter { $0.inputChannelCount > 0 }
    }

    public func currentDefaultInputDevice() throws -> AudioDeviceSnapshot {
        let defaultInputID = try currentDefaultInputDeviceID()
        guard defaultInputID != AudioDeviceID(kAudioObjectUnknown) else {
            throw CoreAudioDeviceError.deviceNotFound(uid: "default-input")
        }
        return try snapshot(for: defaultInputID, defaultInputID: defaultInputID)
    }

    public func resolveDeviceID(uid: String) throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfUID = uid as CFString
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafePointer(to: &cfUID) { qualifier in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<CFString>.size),
                qualifier,
                &dataSize,
                &deviceID
            )
        }
        try check(status, operation: "Translate device UID")
        guard dataSize == UInt32(MemoryLayout<AudioDeviceID>.size) else {
            throw CoreAudioDeviceError.malformedPropertyData(operation: "Translate device UID")
        }
        guard deviceID != AudioDeviceID(kAudioObjectUnknown) else {
            throw CoreAudioDeviceError.deviceNotFound(uid: uid)
        }
        return deviceID
    }

    public func device(uid: String) throws -> AudioDeviceSnapshot {
        let deviceID = try resolveDeviceID(uid: uid)
        let defaultInputID = try currentDefaultInputDeviceID()
        return try snapshot(for: deviceID, defaultInputID: defaultInputID)
    }

    @discardableResult
    public func setDefaultInputDevice(uid: String) throws -> AudioDeviceSnapshot {
        try setDefaultInputDevice(id: resolveDeviceID(uid: uid))
    }

    @discardableResult
    public func setDefaultInputDevice(id targetDeviceID: AudioDeviceID) throws -> AudioDeviceSnapshot {
        var targetDeviceID = targetDeviceID
        let defaultInputID = try currentDefaultInputDeviceID()
        let target = try snapshot(for: targetDeviceID, defaultInputID: defaultInputID)
        guard target.inputChannelCount > 0, target.canBeDefaultInput else {
            throw CoreAudioDeviceError.notInputDefaultCapable(name: target.name)
        }

        var defaultInputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var settable = DarwinBoolean(false)
        try check(
            AudioObjectIsPropertySettable(
                AudioObjectID(kAudioObjectSystemObject),
                &defaultInputAddress,
                &settable
            ),
            operation: "Check default input settable"
        )
        guard settable.boolValue else {
            throw CoreAudioDeviceError.notInputDefaultCapable(name: target.name)
        }

        try check(
            AudioObjectSetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &defaultInputAddress,
                0,
                nil,
                UInt32(MemoryLayout<AudioDeviceID>.size),
                &targetDeviceID
            ),
            operation: "Set default input device"
        )
        return target
    }

    public func startListening(
        queue: DispatchQueue,
        handler: @escaping (CoreAudioDeviceEvent) -> Void
    ) throws {
        try stopListening()

        listenerLock.lock()
        listenerQueue = queue
        listenerHandler = handler
        listenerLock.unlock()

        do {
            try addListener(
                selector: kAudioHardwarePropertyDefaultInputDevice,
                event: .defaultInputChanged,
                queue: queue,
                handler: handler
            )
            try addListener(
                selector: kAudioHardwarePropertyDevices,
                event: .devicesChanged,
                queue: queue,
                handler: handler
            )
            try addListener(
                selector: kAudioHardwarePropertyServiceRestarted,
                event: .serviceRestarted,
                queue: queue,
                handler: handler
            )
        } catch {
            try? stopListening()
            throw error
        }
    }

    public func stopListening() throws {
        listenerLock.lock()
        let registrations = listenerRegistrations
        listenerRegistrations.removeAll()
        listenerQueue = nil
        listenerHandler = nil
        listenerLock.unlock()

        var firstError: CoreAudioDeviceError?
        for registration in registrations {
            var address = registration.address
            let status = AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                registration.queue,
                registration.block
            )
            if status != noErr, firstError == nil {
                firstError = .osStatus(operation: "Remove CoreAudio listener", status: status)
            }
        }
        if let firstError {
            throw firstError
        }
    }

    private func currentDeviceIDs() throws -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        try check(
            AudioObjectGetPropertyDataSize(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &dataSize
            ),
            operation: "Read audio device list size"
        )
        guard dataSize % UInt32(MemoryLayout<AudioDeviceID>.stride) == 0 else {
            throw CoreAudioDeviceError.malformedPropertyData(operation: "Read audio device list")
        }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.stride
        guard count > 0 else {
            return []
        }
        var deviceIDs = Array(repeating: AudioDeviceID(kAudioObjectUnknown), count: count)
        try deviceIDs.withUnsafeMutableBufferPointer { buffer in
            try check(
                AudioObjectGetPropertyData(
                    AudioObjectID(kAudioObjectSystemObject),
                    &address,
                    0,
                    nil,
                    &dataSize,
                    buffer.baseAddress!
                ),
                operation: "Read audio device list"
            )
        }
        guard dataSize == UInt32(count * MemoryLayout<AudioDeviceID>.stride) else {
            throw CoreAudioDeviceError.malformedPropertyData(operation: "Read audio device list")
        }
        return deviceIDs
    }

    private func currentDefaultInputDeviceID() throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var defaultInputID = AudioDeviceID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        try check(
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &dataSize,
                &defaultInputID
            ),
            operation: "Read default input device"
        )
        guard dataSize == UInt32(MemoryLayout<AudioDeviceID>.size) else {
            throw CoreAudioDeviceError.malformedPropertyData(operation: "Read default input device")
        }
        return defaultInputID
    }

    private func snapshot(for deviceID: AudioDeviceID, defaultInputID: AudioDeviceID) throws -> AudioDeviceSnapshot {
        let uid = try readString(
            deviceID: deviceID,
            selector: kAudioDevicePropertyDeviceUID,
            scope: kAudioObjectPropertyScopeGlobal,
            operation: "Read device UID"
        )
        let name = try readString(
            deviceID: deviceID,
            selector: kAudioObjectPropertyName,
            scope: kAudioObjectPropertyScopeGlobal,
            operation: "Read device name"
        )
        let manufacturer = try readOptionalString(
            deviceID: deviceID,
            selector: kAudioObjectPropertyManufacturer,
            scope: kAudioObjectPropertyScopeGlobal,
            operation: "Read device manufacturer"
        )
        let transportType = try readUInt32(
            deviceID: deviceID,
            selector: kAudioDevicePropertyTransportType,
            scope: kAudioObjectPropertyScopeGlobal,
            operation: "Read device transport type"
        )
        let inputChannelCount = try inputChannelCount(deviceID: deviceID)
        let canBeDefaultInput = try canBeDefaultInput(deviceID: deviceID, inputChannelCount: inputChannelCount)
        return AudioDeviceSnapshot(
            id: deviceID,
            uid: uid,
            name: name,
            manufacturer: manufacturer,
            transportType: transportType,
            inputChannelCount: inputChannelCount,
            canBeDefaultInput: canBeDefaultInput,
            isDefaultInput: deviceID == defaultInputID
        )
    }

    private func readString(
        deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        operation: String
    ) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else {
            throw CoreAudioDeviceError.malformedPropertyData(operation: operation)
        }
        var value = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &value) { valuePointer in
            AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &dataSize,
                valuePointer
            )
        }
        try check(
            status,
            operation: operation
        )
        guard dataSize == UInt32(MemoryLayout<CFString>.size) else {
            throw CoreAudioDeviceError.malformedPropertyData(operation: operation)
        }
        return value as String
    }

    private func readOptionalString(
        deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        operation: String
    ) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else {
            return ""
        }
        return try readString(deviceID: deviceID, selector: selector, scope: scope, operation: operation)
    }

    private func readUInt32(
        deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        operation: String
    ) throws -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else {
            throw CoreAudioDeviceError.malformedPropertyData(operation: operation)
        }
        var value: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        try check(
            AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &dataSize,
                &value
            ),
            operation: operation
        )
        guard dataSize == UInt32(MemoryLayout<UInt32>.size) else {
            throw CoreAudioDeviceError.malformedPropertyData(operation: operation)
        }
        return value
    }

    private func inputChannelCount(deviceID: AudioDeviceID) throws -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else {
            return 0
        }
        var dataSize: UInt32 = 0
        try check(
            AudioObjectGetPropertyDataSize(
                deviceID,
                &address,
                0,
                nil,
                &dataSize
            ),
            operation: "Read input stream configuration size"
        )
        guard dataSize >= UInt32(MemoryLayout<UInt32>.size) else {
            throw CoreAudioDeviceError.malformedPropertyData(operation: "Read input stream configuration")
        }

        let rawBuffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBuffer.deallocate() }

        try check(
            AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &dataSize,
                rawBuffer
            ),
            operation: "Read input stream configuration"
        )

        let audioBufferList = rawBuffer.bindMemory(to: AudioBufferList.self, capacity: 1)
        let bufferCount = Int(audioBufferList.pointee.mNumberBuffers)
        let minimumByteCount = bufferCount == 0
            ? MemoryLayout<UInt32>.size
            : MemoryLayout<AudioBufferList>.size + ((bufferCount - 1) * MemoryLayout<AudioBuffer>.stride)
        guard Int(dataSize) >= minimumByteCount else {
            throw CoreAudioDeviceError.malformedPropertyData(operation: "Read input stream configuration")
        }

        var channelCount: UInt32 = 0
        for buffer in UnsafeMutableAudioBufferListPointer(audioBufferList) {
            channelCount += buffer.mNumberChannels
        }
        return channelCount
    }

    private func canBeDefaultInput(deviceID: AudioDeviceID, inputChannelCount: UInt32) throws -> Bool {
        guard inputChannelCount > 0 else {
            return false
        }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceCanBeDefaultDevice,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else {
            return false
        }
        var canBeDefault: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        try check(
            AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &dataSize,
                &canBeDefault
            ),
            operation: "Read input default capability"
        )
        guard dataSize == UInt32(MemoryLayout<UInt32>.size) else {
            throw CoreAudioDeviceError.malformedPropertyData(operation: "Read input default capability")
        }
        return canBeDefault == 1
    }

    private func addListener(
        selector: AudioObjectPropertySelector,
        event: CoreAudioDeviceEvent,
        queue: DispatchQueue,
        handler: @escaping (CoreAudioDeviceEvent) -> Void
    ) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            handler(event)
            if event == .serviceRestarted {
                queue.async { [weak self] in
                    try? self?.reregisterListenersAfterServiceRestart()
                }
            }
        }
        try check(
            AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                queue,
                block
            ),
            operation: "Add CoreAudio listener"
        )

        listenerLock.lock()
        listenerRegistrations.append(ListenerRegistration(address: address, queue: queue, block: block))
        listenerLock.unlock()
    }

    private func reregisterListenersAfterServiceRestart() throws {
        listenerLock.lock()
        guard let queue = listenerQueue, let handler = listenerHandler else {
            listenerLock.unlock()
            return
        }
        listenerLock.unlock()
        try startListening(queue: queue, handler: handler)
    }

    private func check(_ status: OSStatus, operation: String) throws {
        guard status == noErr else {
            throw CoreAudioDeviceError.osStatus(operation: operation, status: status)
        }
    }
}

private extension String {
    func leftPadding(toLength length: Int, withPad pad: Character) -> String {
        let paddingCount = length - count
        guard paddingCount > 0 else {
            return self
        }
        return String(repeating: String(pad), count: paddingCount) + self
    }
}
