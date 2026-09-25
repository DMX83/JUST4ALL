import XCTest
@testable import J4ICore

/// El contador de la bandeja de «Inicio» y la lista de la ventana «Por revisar» comparten
/// `QuarantineListing`: los archivos ocultos (p. ej. `.DS_Store`, que crea Finder al abrir la
/// carpeta) nunca deben contar como elementos pendientes.
final class QuarantineListingTests: XCTestCase {
    private var rootURL: URL!

    private var quarantineURL: URL {
        rootURL.appendingPathComponent(DefaultTaxonomy.quarantineRelativePath, isDirectory: true)
    }

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuarantineListingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: quarantineURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func testIgnoresHiddenFilesLikeDSStore() throws {
        try Data().write(to: quarantineURL.appendingPathComponent(".DS_Store"))
        XCTAssertEqual(QuarantineListing.itemURLs(rootURL: rootURL).count, 0)
    }

    func testCountsFilesAndFolders() throws {
        try Data("factura".utf8).write(to: quarantineURL.appendingPathComponent("factura.pdf"))
        try FileManager.default.createDirectory(
            at: quarantineURL.appendingPathComponent("cajon", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data().write(to: quarantineURL.appendingPathComponent(".oculto"))
        let urls = QuarantineListing.itemURLs(rootURL: rootURL)
        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(Set(urls.map(\.lastPathComponent)), ["factura.pdf", "cajon"])
    }

    func testMissingFolderReturnsEmpty() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuarantineListingTests-sin-carpeta-\(UUID().uuidString)", isDirectory: true)
        XCTAssertEqual(QuarantineListing.itemURLs(rootURL: missing).count, 0)
    }
}
