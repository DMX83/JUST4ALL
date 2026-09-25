import XCTest
import J4ICore
@testable import JUST4DESK

/// F13.0 — Buscador de destino con autocompletado (`DestinationChooser.matches`):
/// escribir filtra la taxonomía sin acentos y conserva el orden padre→hijos.
final class DestinationSearchTests: XCTestCase {
    func testTypingTopLevelShowsItAndItsSubitems() {
        let results = DestinationChooser.matches(query: "trabajo", destinations: DefaultTaxonomy.allRelativePaths)
        XCTAssertEqual(
            results,
            ["05_Trabajo", "05_Trabajo/Contratos", "05_Trabajo/Nominas", "05_Trabajo/Formacion"],
            "escribir «trabajo» debe ofrecer la categoría y TODAS sus subcarpetas"
        )
    }

    func testPartialAndAccentInsensitive() {
        let accented = DestinationChooser.matches(query: "formación", destinations: DefaultTaxonomy.allRelativePaths)
        XCTAssertEqual(accented, ["05_Trabajo/Formacion"], "sin acentos: «formación» encuentra «Formacion»")

        let fiscal = DestinationChooser.matches(query: "fisc", destinations: DefaultTaxonomy.allRelativePaths)
        XCTAssertEqual(fiscal.first, "01_Fiscal", "el padre va primero")
        XCTAssertTrue(fiscal.contains("01_Fiscal/Facturas"))
    }

    func testAllTermsMustMatch() {
        let results = DestinationChooser.matches(query: "trabajo nom", destinations: DefaultTaxonomy.allRelativePaths)
        XCTAssertEqual(results, ["05_Trabajo/Nominas"], "«trabajo nom» descarta las nóminas de Fiscal")
    }

    func testEmptyQueryKeepsFullOrderedList() {
        let all = DefaultTaxonomy.allRelativePaths
        XCTAssertEqual(DestinationChooser.matches(query: "   ", destinations: all), all)
    }

    func testNoMatchReturnsEmpty() {
        XCTAssertTrue(DestinationChooser.matches(query: "zzz", destinations: DefaultTaxonomy.allRelativePaths).isEmpty)
    }

    func testCreateNameSanitization() {
        XCTAssertEqual(DestinationChooser.sanitizedName(from: "  trading  "), "Trading")
        XCTAssertEqual(DestinationChooser.sanitizedName(from: "trading/opciones"), "Trading Opciones", "barras fuera: nunca rutas inesperadas")
        XCTAssertEqual(DestinationChooser.sanitizedName(from: "videos de trading"), "Videos De Trading")
        XCTAssertNil(DestinationChooser.sanitizedName(from: "   "))
        XCTAssertNil(DestinationChooser.sanitizedName(from: "///"))
    }
}
