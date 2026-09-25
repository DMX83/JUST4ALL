import XCTest
@testable import JUST4INDEX

/// N4 — varias carpetas de entrada: helpers puros de la configuración
/// (añadir estandarizando y sin duplicados; quitar por ruta estandarizada).
final class FilingConfigurationTests: XCTestCase {
    func testAddingStandardizesAndDeduplicates() {
        let first = FilingConfiguration.adding("/Users/dmx83/Descargas", to: [])
        XCTAssertEqual(first, ["/Users/dmx83/Descargas"])

        let second = FilingConfiguration.adding("/Users/dmx83/Downloads", to: first)
        XCTAssertEqual(second, ["/Users/dmx83/Descargas", "/Users/dmx83/Downloads"])

        // Repetir la misma carpeta (con barra final) no duplica ni reordena.
        let again = FilingConfiguration.adding("/Users/dmx83/Downloads/", to: second)
        XCTAssertEqual(again, second)
    }

    func testRemovingFiltersByStandardizedPath() {
        let paths = ["/Users/dmx83/Descargas", "/Users/dmx83/Downloads"]
        XCTAssertEqual(FilingConfiguration.removing("/Users/dmx83/Downloads/", from: paths), ["/Users/dmx83/Descargas"])
        XCTAssertEqual(FilingConfiguration.removing("/Users/dmx83/Descargas", from: paths), ["/Users/dmx83/Downloads"])
        XCTAssertEqual(FilingConfiguration.removing("/ruta/inexistente", from: paths), paths)
    }
}
