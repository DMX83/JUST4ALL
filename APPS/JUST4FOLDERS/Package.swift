// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "JUST4FOLDERS",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "JUST4FOLDERS", targets: ["JUST4FOLDERS"]),
        // Libraries de este paquete (el resto de motores viven en PACKAGES/J4SHARED).
        .library(name: "J4FOps", targets: ["J4FOps"]),
        .library(name: "J4FUI", targets: ["J4FUI"])
    ],
    dependencies: [
        // Motores compartidos: J4FCore/J4FFileSystem (y, para la búsqueda, J4IIndex).
        .package(path: "../../PACKAGES/J4SHARED")
    ],
    targets: [
        .target(
            name: "J4FOps",
            dependencies: [
                .product(name: "J4FCore", package: "J4SHARED"),
                .product(name: "J4FFileSystem", package: "J4SHARED")
            ]
        ),
        .target(
            name: "J4FUI",
            dependencies: [
                .product(name: "J4FCore", package: "J4SHARED"),
                .product(name: "J4FFileSystem", package: "J4SHARED"),
                "J4FOps"
            ]
        ),
        .executableTarget(
            name: "JUST4FOLDERS",
            dependencies: [
                "J4FUI",
                "J4FOps",
                .product(name: "J4FCore", package: "J4SHARED"),
                .product(name: "J4FFileSystem", package: "J4SHARED"),
                // Ladrillo v1.1: búsqueda del commander sobre el índice FTS5 compartido.
                .product(name: "J4IIndex", package: "J4SHARED")
            ]
        ),
        .testTarget(
            name: "J4FOpsTests",
            dependencies: [
                "J4FOps",
                .product(name: "J4FFileSystem", package: "J4SHARED")
            ]
        )
    ]
)
