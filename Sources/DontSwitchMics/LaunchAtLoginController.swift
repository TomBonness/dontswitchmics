import Foundation
import ServiceManagement

enum LaunchAtLoginController {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static var fallbackLaunchAgentInstalled: Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            do {
                try SMAppService.mainApp.register()
            } catch {
                if shouldUseLaunchAgentFallback {
                    try installLaunchAgentFallback()
                    return
                }
                throw error
            }
            if status == .notFound, shouldUseLaunchAgentFallback {
                try installLaunchAgentFallback()
            }
        } else {
            if fallbackLaunchAgentInstalled {
                try FileManager.default.removeItem(at: launchAgentURL)
            }
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static var shouldUseLaunchAgentFallback: Bool {
        Bundle.main.bundleURL.path == "/Applications/DontSwitchMics.app"
    }

    private static var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("com.tombonness.dontswitchmics.plist")
    }

    private static func installLaunchAgentFallback() throws {
        guard let executableURL = Bundle.main.executableURL else {
            throw LaunchAtLoginError.missingExecutableURL
        }
        let launchAgentsDirectory = launchAgentURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: launchAgentsDirectory,
            withIntermediateDirectories: true
        )
        let plist: [String: Any] = [
            "Label": "com.tombonness.dontswitchmics",
            "Program": executableURL.path,
            "RunAtLoad": true
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: launchAgentURL, options: .atomic)
    }
}

enum LaunchAtLoginError: Error, CustomStringConvertible {
    case missingExecutableURL

    var description: String {
        switch self {
        case .missingExecutableURL:
            return "Cannot determine the app executable path for launch at login"
        }
    }
}
