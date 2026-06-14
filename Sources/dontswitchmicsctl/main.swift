import Darwin
import DontSwitchMicsCore
import Foundation

private enum ExitCode: Int32 {
    case success = 0
    case userOrDeviceSelection = 2
    case coreAudio = 3
    case unexpectedArgument = 4
}

private enum CLIError: Error, CustomStringConvertible {
    case unexpectedArguments([String])
    case missingValue(String)
    case invalidSeconds(String)
    case noEligibleDeviceNamed(String, candidates: [AudioDeviceSnapshot])
    case noEligibleDeviceWithUID(String, candidates: [AudioDeviceSnapshot])
    case ambiguousDeviceName(String, candidates: [AudioDeviceSnapshot])

    var description: String {
        switch self {
        case let .unexpectedArguments(arguments):
            return "Unexpected arguments: \(arguments.joined(separator: " "))"
        case let .missingValue(option):
            return "Missing value for \(option)"
        case let .invalidSeconds(value):
            return "Invalid --exit-after-seconds value: \(value)"
        case let .noEligibleDeviceNamed(name, _):
            return "No input/default-capable device is named \"\(name)\""
        case let .noEligibleDeviceWithUID(uid, _):
            return "No input/default-capable device has UID \"\(uid)\""
        case let .ambiguousDeviceName(name, _):
            return "More than one input/default-capable device is named \"\(name)\""
        }
    }

    var candidates: [AudioDeviceSnapshot]? {
        switch self {
        case let .noEligibleDeviceNamed(_, candidates),
             let .noEligibleDeviceWithUID(_, candidates),
             let .ambiguousDeviceName(_, candidates):
            return candidates
        default:
            return nil
        }
    }
}

private enum Command {
    case listDevices
    case currentDefaultInput
    case selectDeviceName(String)
    case selectDeviceUID(String)
    case setDefaultInputName(String)
    case setDefaultInputUID(String)
    case enforceOnce
    case runAgent(exitAfterSeconds: TimeInterval)
}

private let client = CoreAudioDeviceClient()
private let controller = MicLockController(deviceClient: client)

do {
    let command = try parseCommand(Array(CommandLine.arguments.dropFirst()))
    let exitCode = try run(command)
    exit(exitCode.rawValue)
} catch let error as CLIError {
    fputs(error.description + "\n", stderr)
    if let candidates = error.candidates {
        printJSON(candidates)
    }
    exit(exitCode(for: error).rawValue)
} catch let error as CoreAudioDeviceError {
    fputs(error.description + "\n", stderr)
    exit(exitCode(for: error).rawValue)
} catch {
    fputs(String(describing: error) + "\n", stderr)
    exit(ExitCode.coreAudio.rawValue)
}

private func parseCommand(_ arguments: [String]) throws -> Command {
    guard let first = arguments.first else {
        throw CLIError.unexpectedArguments(arguments)
    }

    switch first {
    case "--list-devices":
        guard arguments.count == 1 else { throw CLIError.unexpectedArguments(arguments) }
        return .listDevices
    case "--current-default-input":
        guard arguments.count == 1 else { throw CLIError.unexpectedArguments(arguments) }
        return .currentDefaultInput
    case "--select-device-name":
        return .selectDeviceName(try singleValue(arguments, option: first))
    case "--select-device-uid":
        return .selectDeviceUID(try singleValue(arguments, option: first))
    case "--set-default-input-name":
        return .setDefaultInputName(try singleValue(arguments, option: first))
    case "--set-default-input-uid":
        return .setDefaultInputUID(try singleValue(arguments, option: first))
    case "--enforce-once":
        guard arguments.count == 1 else { throw CLIError.unexpectedArguments(arguments) }
        return .enforceOnce
    case "--run-agent":
        guard arguments.count == 3, arguments[1] == "--exit-after-seconds" else {
            throw CLIError.unexpectedArguments(arguments)
        }
        guard let seconds = TimeInterval(arguments[2]), seconds >= 0 else {
            throw CLIError.invalidSeconds(arguments[2])
        }
        return .runAgent(exitAfterSeconds: seconds)
    default:
        throw CLIError.unexpectedArguments(arguments)
    }
}

private func singleValue(_ arguments: [String], option: String) throws -> String {
    guard arguments.count >= 2 else {
        throw CLIError.missingValue(option)
    }
    guard arguments.count == 2 else {
        throw CLIError.unexpectedArguments(arguments)
    }
    return arguments[1]
}

private func run(_ command: Command) throws -> ExitCode {
    switch command {
    case .listDevices:
        printJSON(try client.devices())
        return .success
    case .currentDefaultInput:
        printJSON(try client.currentDefaultInputDevice())
        return .success
    case let .selectDeviceName(name):
        let device = try exactlyOneEligibleDevice(named: name)
        try controller.selectPreferredDevice(uid: device.uid)
        print("Selected \(device.name) (\(device.uid))")
        return .success
    case let .selectDeviceUID(uid):
        let device = try eligibleDevice(uid: uid)
        try controller.selectPreferredDevice(uid: device.uid)
        print("Selected \(device.name) (\(device.uid))")
        return .success
    case let .setDefaultInputName(name):
        let device = try exactlyOneEligibleDevice(named: name)
        try client.setDefaultInputDevice(uid: device.uid)
        print("Set default input to \(device.name) (\(device.uid))")
        return .success
    case let .setDefaultInputUID(uid):
        let device = try eligibleDevice(uid: uid)
        try client.setDefaultInputDevice(uid: device.uid)
        print("Set default input to \(device.name) (\(device.uid))")
        return .success
    case .enforceOnce:
        let result = controller.enforce(reason: .cli)
        print(result.userVisibleText)
        switch result {
        case .locked, .alreadyLocked:
            return .success
        case .disabled, .needsSelection, .targetMissing:
            return .userOrDeviceSelection
        case .failed:
            return .coreAudio
        }
    case let .runAgent(exitAfterSeconds):
        let agentController = MicLockController(deviceClient: client) { reason, result in
            print("\(reason.rawValue): \(result.userVisibleText)")
            fflush(stdout)
        }
        try agentController.startAutomaticEnforcement()
        let startupResult = agentController.enforce(reason: .startup)
        print("startup: \(startupResult.userVisibleText)")
        fflush(stdout)
        RunLoop.current.run(until: Date().addingTimeInterval(exitAfterSeconds))
        try agentController.stopAutomaticEnforcement()
        return .success
    }
}

private func eligibleDevices() throws -> [AudioDeviceSnapshot] {
    try client.devices()
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

private func exactlyOneEligibleDevice(named name: String) throws -> AudioDeviceSnapshot {
    let candidates = try eligibleDevices()
    let matches = candidates.filter { $0.name == name }
    guard let first = matches.first else {
        throw CLIError.noEligibleDeviceNamed(name, candidates: candidates)
    }
    guard matches.count == 1 else {
        throw CLIError.ambiguousDeviceName(name, candidates: candidates)
    }
    return first
}

private func eligibleDevice(uid: String) throws -> AudioDeviceSnapshot {
    let candidates = try eligibleDevices()
    guard let device = candidates.first(where: { $0.uid == uid }) else {
        throw CLIError.noEligibleDeviceWithUID(uid, candidates: candidates)
    }
    return device
}

private func printJSON<T: Encodable>(_ value: T) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
        let data = try encoder.encode(value)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    } catch {
        fputs("Failed to encode JSON: \(error)\n", stderr)
        exit(ExitCode.coreAudio.rawValue)
    }
}

private func exitCode(for error: CLIError) -> ExitCode {
    switch error {
    case .unexpectedArguments, .missingValue, .invalidSeconds:
        return .unexpectedArgument
    case .noEligibleDeviceNamed, .noEligibleDeviceWithUID, .ambiguousDeviceName:
        return .userOrDeviceSelection
    }
}

private func exitCode(for error: CoreAudioDeviceError) -> ExitCode {
    switch error {
    case .deviceNotFound, .deviceNameNotUnique, .notInputDefaultCapable:
        return .userOrDeviceSelection
    case .osStatus, .malformedPropertyData:
        return .coreAudio
    }
}
