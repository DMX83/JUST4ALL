// swift-tools-version: 5.9
import PackageDescription

// JUST4DESK — buscador instantáneo (SQLite FTS5) + organizador inteligente de documentos.
// Reutiliza el motor de operaciones de JUST4FOLDERS (J4FFileSystem/J4FOps) vía dependencia local.
let package = Package(
    name: "JUST4DESK",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "JUST4DESK", targets: ["JUST4DESK"]),
        .library(name: "J4ICore", targets: ["J4ICore"]),
        .library(name: "J4IIndex", targets: ["J4IIndex"]),
        .library(name: "J4IDocs", targets: ["J4IDocs"]),
        .library(name: "J4IAI", targets: ["J4IAI"]),
        .library(name: "J4IFiling", targets: ["J4IFiling"])
    ],
    dependencies: [
        .package(path: "../JUST4FOLDERS")
    ],
    targets: [
        .target(name: "J4ICore"),
        .target(
            name: "J4IIndex",
            dependencies: [
                "J4ICore",
                .product(name: "J4FFileSystem", package: "JUST4FOLDERS")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .target(
            name: "J4IDocs",
            dependencies: ["J4ICore"]
        ),
        .target(
            name: "J4IAI",
            dependencies: ["J4ICore", "J4IDocs"]
        ),
        .target(
            name: "J4IFiling",
            dependencies: [
                "J4ICore",
                "J4IDocs",
                "J4IAI",
                "J4IIndex",
                .product(name: "J4FFileSystem", package: "JUST4FOLDERS"),
                .product(name: "J4FOps", package: "JUST4FOLDERS")
            ]
        ),
        .executableTarget(
            name: "JUST4DESK",
            dependencies: ["J4ICore", "J4IIndex", "J4IDocs", "J4IAI", "J4IFiling"]
        ),
        .testTarget(
            name: "J4ICoreTests",
            dependencies: ["J4ICore"]
        ),
        .testTarget(
            name: "J4IDocsTests",
            dependencies: ["J4IDocs"]
        ),
        .testTarget(
            name: "J4IAITests",
            dependencies: ["J4IAI"]
        ),
        .testTarget(
            name: "J4IFilingTests",
            dependencies: ["J4IFiling", "J4IIndex", "J4ICore"]
        ),
        .testTarget(
            name: "J4IIndexTests",
            dependencies: ["J4IIndex"]
        ),
        .testTarget(
            name: "JUST4DESKTests",
            dependencies: ["JUST4DESK", "J4IIndex"]
        )
    ]
)
