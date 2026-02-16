// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "JUST4ALL",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "JUST4ALL", targets: ["JUST4ALL"])
    ],
    targets: [
        .executableTarget(
            name: "JUST4ALL",
            path: "Sources/JUST4ALL",
            exclude: [
                "Resources/Info.plist"
            ],
            resources: [
                // Do not bundle the app Info.plist; it's used by Xcode/build scripts.
                .copy("Resources/Assets"),
                .copy("Resources/Downloads")
            ]
        )
    ]
)
