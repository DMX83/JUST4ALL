// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "JUST4PICT",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "JUST4PICT", targets: ["JUST4PICT"])
    ],
    targets: [
        .executableTarget(name: "JUST4PICT"),
        .testTarget(
            name: "JUST4PICTTests",
            dependencies: ["JUST4PICT"]
        )
    ]
)
