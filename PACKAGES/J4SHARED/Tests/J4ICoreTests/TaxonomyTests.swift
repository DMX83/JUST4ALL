import XCTest
import J4ICore

final class TaxonomyTests: XCTestCase {
    func testSeedContainsTopLevelCategories() {
        let categories = DefaultTaxonomy.categories()
        XCTAssertEqual(categories.count, 17)
        XCTAssertTrue(categories.contains { $0.name == DefaultTaxonomy.coldArchiveRelativePath })
        XCTAssertEqual(categories.first?.name, "01_Fiscal")
        XCTAssertEqual(categories.last?.name, DefaultTaxonomy.quarantineRelativePath)
        XCTAssertTrue(categories.contains { $0.name == "12_Software" })
        XCTAssertTrue(categories.contains { $0.name == "13_Multimedia" })
        XCTAssertTrue(categories.contains { $0.name == "14_Comprimidos" })
        XCTAssertTrue(categories.contains { $0.name == "15_Libros" })
    }

    func testAllRelativePathsIncludeChildren() {
        let paths = DefaultTaxonomy.allRelativePaths
        XCTAssertTrue(paths.contains("01_Fiscal"))
        XCTAssertTrue(paths.contains("01_Fiscal/Facturas"))
        XCTAssertTrue(paths.contains(DefaultTaxonomy.quarantineRelativePath))
        XCTAssertTrue(paths.contains("13_Multimedia/Peliculas"))
        XCTAssertTrue(paths.contains("13_Multimedia/Series"))
        XCTAssertTrue(paths.contains("13_Multimedia/Documentales"))
        XCTAssertTrue(paths.contains("13_Multimedia/Audiolibros"))
        XCTAssertTrue(paths.contains("13_Multimedia/Musica"))
        XCTAssertTrue(paths.contains("06_Educacion/Cursos"))
        XCTAssertTrue(paths.contains("15_Libros"))
        XCTAssertTrue(paths.contains("12_Software/Redes"))
        XCTAssertGreaterThan(paths.count, 30)
    }

    func testInstallerCreatesFullTree() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-taxonomy-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let report = TaxonomyInstaller.install(at: root)
        XCTAssertTrue(report.conflicts.isEmpty)
        XCTAssertTrue(report.existing.isEmpty)
        XCTAssertEqual(report.created.count, DefaultTaxonomy.allRelativePaths.count)

        for relativePath in DefaultTaxonomy.allRelativePaths {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: root.appendingPathComponent(relativePath).path,
                isDirectory: &isDirectory
            )
            XCTAssertTrue(exists, "Falta \(relativePath)")
            XCTAssertTrue(isDirectory.boolValue, "\(relativePath) no es carpeta")
        }
    }

    func testInstallerIsIdempotent() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-taxonomy-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let first = TaxonomyInstaller.install(at: root)
        XCTAssertFalse(first.created.isEmpty)

        let second = TaxonomyInstaller.install(at: root)
        XCTAssertTrue(second.created.isEmpty)
        XCTAssertEqual(second.existing.count, DefaultTaxonomy.allRelativePaths.count)
        XCTAssertTrue(second.conflicts.isEmpty)
    }

    func testInstallerReportsConflictsWhenFileBlocksDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-taxonomy-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("01_Fiscal"))

        let report = TaxonomyInstaller.install(at: root)
        XCTAssertTrue(report.conflicts.contains("01_Fiscal"))
        XCTAssertTrue(report.created.contains("02_Banca"))
        XCTAssertTrue(report.created.contains(DefaultTaxonomy.quarantineRelativePath))
    }
}
