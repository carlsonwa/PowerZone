// swift-tools-version: 5.9

// Swift Playgrounds app project. Open PowerZoneRide.swiftpm on the iPad in Swift
// Playgrounds; there is no Xcode step. Bluetooth is declared here rather than through
// the App Settings UI so the capability survives a fresh clone.

import AppleProductTypes
import PackageDescription

let package = Package(
    name: "PowerZoneRide",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "PowerZone Ride",
            targets: ["AppModule"],
            bundleIdentifier: "com.carlsonwa.powerzoneride",
            teamIdentifier: "",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .bicycle),
            accentColor: .presetColor(.orange),
            supportedDeviceFamilies: [.pad],
            // Landscape only: the chart needs the width, and the iPad is clamped to a
            // handlebar mount that does not rotate.
            supportedInterfaceOrientations: [
                .landscapeRight,
                .landscapeLeft
            ],
            capabilities: [
                .bluetoothAlways(purposeString:
                    "PowerZone Ride connects to your bike's power meter to chart your live power output against the workout's target zones.")
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: ".",
            resources: [
                .copy("Data/Fixtures")
            ]
        )
    ]
)
