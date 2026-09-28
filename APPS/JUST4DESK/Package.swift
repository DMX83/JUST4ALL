// swift-tools-version: 5.9
import PackageDescription

// JUST4DESK — buscador instantáneo (SQLite FTS5) + organizador inteligente de documentos.
// Los motores compartidos (J4ICore/J4IIndex) viven en PACKAGES/J4SHARED, junto a los de
// JUST4FOLDERS (J4FCore/J4FFileSystem): un solo hogar y sin dependencias cruzadas entre apps.
let package = Package(
    name: "JUST4DESK",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "JUST4DESK", targets: ["JUST4DESK"]),
        .executable(name: "JUST4DESKMCP", targets: ["JUST4DESKMCP"]),
        .library(name: "J4IDocs", targets: ["J4IDocs"]),
        .library(name: "J4IAI", targets: ["J4IAI"]),
        .library(name: "J4IFiling", targets: ["J4IFiling"]),
        .library(name: "J4IMCP", targets: ["J4IMCP"])
    ],
    dependencies: [
        .package(path: "../../PACKAGES/J4SHARED")
    ],
    targets: [
        .target(
            name: "J4IDocs",
            dependencies: [
                .product(name: "J4ICore", package: "J4SHARED")
            ]
        ),
        .target(
            name: "J4IAI",
            dependencies: [
                "J4IDocs",
                .product(name: "J4ICore", package: "J4SHARED")
            ]
        ),
        .target(
            name: "J4IFiling",
            dependencies: [
                "J4IDocs",
                "J4IAI",
                .product(name: "J4ICore", package: "J4SHARED"),
                .product(name: "J4IIndex", package: "J4SHARED")
            ]
        ),
        .executableTarget(
            name: "JUST4DESK",
            dependencies: [
                "J4IDocs",
                "J4IAI",
                "J4IFiling",
                .product(name: "J4ICore", package: "J4SHARED"),
                .product(name: "J4IIndex", package: "J4SHARED")
            ]
        ),
        .target(
            name: "J4IMCP",
            dependencies: [
                "J4IDocs",
                .product(name: "J4ICore", package: "J4SHARED"),
                .product(name: "J4IIndex", package: "J4SHARED")
            ]
        ),
        .executableTarget(
            name: "JUST4DESKMCP",
            dependencies: ["J4IMCP"]
        ),
        .testTarget(
            name: "J4IDocsTests",
            dependencies: [
                "J4IDocs",
                .product(name: "J4ICore", package: "J4SHARED")
            ]
        ),
        .testTarget(
            name: "J4IAITests",
            dependencies: [
                "J4IAI",
                .product(name: "J4ICore", package: "J4SHARED")
            ]
        ),
        .testTarget(
            name: "J4IFilingTests",
            dependencies: [
                "J4IFiling",
                .product(name: "J4ICore", package: "J4SHARED"),
                .product(name: "J4IIndex", package: "J4SHARED")
            ]
        ),
        .testTarget(
            name: "JUST4DESKTests",
            dependencies: [
                "JUST4DESK",
                .product(name: "J4ICore", package: "J4SHARED"),
                .product(name: "J4IIndex", package: "J4SHARED")
            ]
        ),
        .testTarget(
            name: "J4IMCPTests",
            dependencies: [
                "J4IMCP",
                .product(name: "J4ICore", package: "J4SHARED"),
                .product(name: "J4IIndex", package: "J4SHARED")
            ]
        )
    ]
)
