// swift-tools-version: 5.9

// Swift Playgrounds app project. Open Kinboard.swiftpm on an iPad (or a Mac) in Swift
// Playgrounds; there is no Xcode step. The camera capability is declared here rather than
// through the App Settings UI so it survives a fresh clone. No icon is set, so Playgrounds
// shows its default; choose one in App Settings and Playgrounds will add it here.

import AppleProductTypes
import PackageDescription

let package = Package(
    name: "Kinboard",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "Kinboard",
            targets: ["AppModule"],
            bundleIdentifier: "com.carlsonwa.kinboard",
            teamIdentifier: "",
            displayVersion: "1.0",
            bundleVersion: "1",
            accentColor: .presetColor(.orange),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ],
            capabilities: [
                .camera(purposeString:
                    "Kinboard uses the camera to scan paper notes and flyers from school so it can pull out the dates and to-dos.")
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "."
        )
    ]
)
