import XCTest
@testable import JUST4DESK
import J4IIndex

/// G4 — modelo del buscador rápido (⌥Espacio): búsqueda contra el índice inyectado, aviso si el
/// fichero ya no existe y puente a la ventana completa (`j4iOpenSearch` con la consulta).
@MainActor
final class QuickSearchModelTests: XCTestCase {
    private var tempDir: URL!
    private var index: SearchIndex!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4d-quicksearch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        index = SearchIndex(databaseURL: tempDir.appendingPathComponent("index.sqlite"))
    }

    override func tearDownWithError() throws {
        index = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func seedIndex() async throws {
        let root = tempDir.appendingPathComponent("archivo", isDirectory: true).path
        let rootEntry = try await index.addRoot(path: root)
        try await index.upsertEntries(rootID: rootEntry.id, [
            IndexEntryWrite(path: "\(root)/Factura-Luz-2026.pdf", isDirectory: false, sizeBytes: 100, modifiedAt: Date()),
            IndexEntryWrite(path: "\(root)/Notas.txt", isDirectory: false, sizeBytes: 10, modifiedAt: Date())
        ])
    }

    func testSearchReturnsHitsAndClearsOnEmptyQuery() async throws {
        try await seedIndex()
        let model = QuickSearchModel(index: index)

        model.query = "factura"
        await model.performSearch()
        XCTAssertEqual(model.hits.first?.entry.name, "Factura-Luz-2026.pdf")

        model.query = "   "
        await model.performSearch()
        XCTAssertTrue(model.hits.isEmpty, "consulta vacía limpia resultados")
    }

    func testOpenMissingFileReportsError() async throws {
        try await seedIndex()
        let model = QuickSearchModel(index: index)
        model.query = "factura"
        await model.performSearch()
        let hit = try XCTUnwrap(model.hits.first)

        // La entrada está indexada pero el fichero no existe en disco: aviso, sin abrir nada.
        XCTAssertFalse(model.open(hit))
        XCTAssertNotNil(model.errorMessage)
    }

    func testOpenFullSearchPostsQuery() async throws {
        let model = QuickSearchModel(index: index)
        var received: String?
        let observer = NotificationCenter.default.addObserver(forName: .j4iOpenSearch, object: nil, queue: nil) { note in
            received = note.object as? String
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        model.query = "dune"
        model.openFullSearch()
        XCTAssertEqual(received, "dune")

        model.query = ""
        model.openFullSearch()
        XCTAssertNil(received)
    }
}
