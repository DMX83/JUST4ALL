import XCTest
@testable import J4ICore

/// F14.0 — Inventario de categorías en disco: la taxonomía de fábrica ∪ las carpetas que existan
/// de verdad en la raíz (categorías creadas al momento, subcarpetas a mano…), sin la cuarentena.
final class TaxonomyInventoryTests: XCTestCase {
    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-inventory-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func testInventoryMergesDefaultTaxonomyWithOnDiskFolders() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = TaxonomyInstaller.install(at: root)

        // Categoría nueva creada «al vuelo» + subcarpeta a mano dentro de una categoría clásica.
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Trading/Opciones", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("05_Trabajo/Presupuestos", isDirectory: true), withIntermediateDirectories: true)

        let destinations = TaxonomyInventory.availableDestinations(rootURL: root)
        XCTAssertTrue(destinations.contains("Trading"), "la categoría creada aparece como destino")
        XCTAssertTrue(destinations.contains("Trading/Opciones"), "y también sus subcarpetas")
        XCTAssertTrue(destinations.contains("05_Trabajo/Presupuestos"), "una subcarpeta creada a mano también aparece")
        XCTAssertTrue(destinations.contains("05_Trabajo/Nominas"), "las subcarpetas de fábrica siguen ahí")
        XCTAssertFalse(destinations.contains(DefaultTaxonomy.quarantineRelativePath))
        XCTAssertEqual(destinations.first, "01_Fiscal", "la taxonomía de fábrica va primero")
    }

    func testQuarantineChildrenAreNotDestinations() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = TaxonomyInstaller.install(at: root)

        // Una carpeta-unidad en cuarentena (p. ej. «Documents») NO debe ofrecerse como destino.
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("99_SinClasificar/Documents", isDirectory: true),
            withIntermediateDirectories: true
        )

        let destinations = TaxonomyInventory.availableDestinations(rootURL: root)
        XCTAssertFalse(destinations.contains("99_SinClasificar/Documents"))
        XCTAssertFalse(destinations.contains { $0.hasPrefix("99_SinClasificar/") })
    }

    func testCustomCategoryResolvesThroughThePlanner() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = TaxonomyInstaller.install(at: root)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Trading", isDirectory: true), withIntermediateDirectories: true)

        let categories = TaxonomyInventory.categories(rootURL: root)
        let plan = FilingPlanner.resolve(
            proposal: FilingProposal(categoryPath: "trading", confidence: 0.8, reason: "prueba", source: .ai),
            originalFileName: "seminario-scalping.mp4",
            categories: categories
        )
        XCTAssertEqual(plan.categoryRelativePath, "Trading", "el planificador acepta la categoría nueva (matching sin caso/acentos)")
    }
}
