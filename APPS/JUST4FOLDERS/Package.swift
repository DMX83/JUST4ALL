// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "JUST4FOLDERS",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "JUST4FOLDERS", targets: ["JUST4FOLDERS"]),
        // Library products para reuso desde otras subapps del monorepo (p. ej. JUST4DESK).
        .library(name: "J4FCore", targets: ["J4FCore"]),
        .library(name: "J4FFileSystem", targets: ["J4FFileSystem"]),
        .library(name: "J4FOps", targets: ["J4FOps"]),
        .library(name: "J4FUI", targets: ["J4FUI"])
    ],
    targets: [
        .target(name: "J4FCore"),
        .target(
            name: "J4FFileSystem",
            dependencies: ["J4FCore"],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .target(
            name: "J4FOps",
            dependencies: ["J4FCore", "J4FFileSystem"]
        ),
        .target(
            name: "J4FUI",
            dependencies: ["J4FCore", "J4FFileSystem", "J4FOps"]
        ),
        .executableTarget(
            name: "JUST4FOLDERS",
            dependencies: ["J4FUI", "J4FOps", "J4FFileSystem", "J4FCore"]
        ),
        .testTarget(
            name: "J4FOpsTests",
            dependencies: ["J4FOps", "J4FFileSystem"]
        ),
        .testTarget(
            name: "J4FFileSystemTests",
            dependencies: ["J4FFileSystem"]
        )
    ]
)
