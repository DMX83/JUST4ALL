// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "JUST4CONVERT",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "JUST4CONVERT", targets: ["JUST4CONVERT"])
    ],
    targets: [
        .executableTarget(
            name: "JUST4CONVERT",
            resources: [
                .copy("ffmpeg")
            ]
        )
    ]
)
