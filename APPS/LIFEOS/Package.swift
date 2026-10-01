// swift-tools-version: 5.9
import PackageDescription

// LIFEOS — cliente nativo de macOS para LifeOS (https://lifeos.perlatec.net).
//
// Habla directamente con la API de LifeOS: no incrusta la web ni necesita un
// servidor propio. El alcance es el ciclo diario (capturar → confirmar → hoy →
// bandeja), no las doce secciones del producto web.
//
// Capas, de abajo arriba y sin saltos:
//   LifeOSAPI   red y contrato JSON (sin UI)
//   LifeOSCore  dominio local: llavero, ajustes, cola sin conexión y sesión
//   LifeOSUI    vistas SwiftUI y tokens del sistema de diseño de LifeOS
//   LIFEOS      ejecutable: composición, menú de barra, atajo global y avisos
let package = Package(
    name: "LIFEOS",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LIFEOS", targets: ["LIFEOS"]),
        .executable(name: "lifeos-doctor", targets: ["LifeOSDoctor"]),
        .library(name: "LifeOSAPI", targets: ["LifeOSAPI"]),
        .library(name: "LifeOSCore", targets: ["LifeOSCore"]),
        .library(name: "LifeOSUI", targets: ["LifeOSUI"])
    ],
    targets: [
        .target(name: "LifeOSAPI"),
        .target(name: "LifeOSCore", dependencies: ["LifeOSAPI"]),
        .target(name: "LifeOSUI", dependencies: ["LifeOSAPI", "LifeOSCore"]),
        .executableTarget(
            name: "LIFEOS",
            dependencies: ["LifeOSAPI", "LifeOSCore", "LifeOSUI"]
        ),
        // Diagnóstico del servidor desde la terminal (`lifeos-doctor`), sin
        // AppKit: se puede usar en un script y no hay ventana de por medio.
        .executableTarget(
            name: "LifeOSDoctor",
            dependencies: ["LifeOSAPI", "LifeOSCore"]
        ),
        .target(name: "TestSupport", path: "Tests/TestSupport"),
        .testTarget(
            name: "LifeOSAPITests",
            dependencies: ["LifeOSAPI", "TestSupport"]
        ),
        .testTarget(
            name: "LifeOSCoreTests",
            dependencies: ["LifeOSCore", "LifeOSAPI", "TestSupport"]
        ),
        // Contra un servidor real: se salta solo si falta `LIFEOS_LIVE_SERVER`.
        .testTarget(
            name: "LifeOSLiveTests",
            dependencies: ["LifeOSCore", "LifeOSAPI"]
        ),
        // Imágenes de revisión de diseño (render fuera de pantalla).
        .testTarget(
            name: "LifeOSUITests",
            dependencies: ["LifeOSUI", "LifeOSCore", "LifeOSAPI"]
        )
    ]
)
