// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "iCrashDiag",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "iCrashDiag",
            path: "iCrashDiag",
            resources: [
                .copy("Resources/knowledge")
            ]
        )
    ]
)
