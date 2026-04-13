// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "iCrashDiag",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "iCrashDiag",
            path: "iCrashDiag",
            resources: [
                .copy("Resources/knowledge"),
                .copy("Resources/samples"),
                .process("Resources/en.lproj"),
                .process("Resources/fr.lproj"),
                .process("Resources/de.lproj"),
                .process("Resources/es.lproj"),
                .process("Resources/it.lproj"),
                .process("Resources/pt.lproj"),
                .process("Resources/nl.lproj"),
                .process("Resources/ja.lproj"),
                .process("Resources/ko.lproj"),
                .process("Resources/zh-Hans.lproj"),
                .process("Resources/ar.lproj"),
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
            ]
        )
    ]
)
