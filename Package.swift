// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DontSwitchMics",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "DontSwitchMics", targets: ["DontSwitchMics"]),
        .executable(name: "dontswitchmicsctl", targets: ["dontswitchmicsctl"])
    ],
    targets: [
        .target(name: "DontSwitchMicsCore"),
        .executableTarget(
            name: "DontSwitchMics",
            dependencies: ["DontSwitchMicsCore"]
        ),
        .executableTarget(
            name: "dontswitchmicsctl",
            dependencies: ["DontSwitchMicsCore"]
        ),
        .testTarget(
            name: "DontSwitchMicsCoreTests",
            dependencies: ["DontSwitchMicsCore"]
        )
    ]
)
