// swift-tools-version: 5.9
import PackageDescription

// J4SHARED — motores compartidos del ecosistema JUST4ALL (paquete local).
//
//  · J4FCore / J4FFileSystem — base de sistema de ficheros (enumeración, índices de path,
//    motor de copia auxiliar). Origen: JUST4FOLDERS.
//  · J4ICore / J4IIndex       — núcleo de dominio (taxonomía, planes, log J4Log) y el índice
//    FTS5 instantáneo. Origen: JUST4DESK.
//
// Consumido por APPS/JUST4FOLDERS (commander) y APPS/JUST4DESK (buscador + organizador).
// Objetivo: un único hogar para los motores; evita dependencias cruzadas entre apps.
let package = Package(
    name: "J4SHARED",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "J4FCore", targets: ["J4FCore"]),
        .library(name: "J4FFileSystem", targets: ["J4FFileSystem"]),
        .library(name: "J4ICore", targets: ["J4ICore"]),
        .library(name: "J4IIndex", targets: ["J4IIndex"])
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
        .target(name: "J4ICore"),
        .target(
            name: "J4IIndex",
            dependencies: ["J4ICore"],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "J4FFileSystemTests",
            dependencies: ["J4FFileSystem"]
        ),
        .testTarget(
            name: "J4ICoreTests",
            dependencies: ["J4ICore"]
        ),
        .testTarget(
            name: "J4IIndexTests",
            dependencies: ["J4IIndex", "J4ICore"]
        )
    ]
)
