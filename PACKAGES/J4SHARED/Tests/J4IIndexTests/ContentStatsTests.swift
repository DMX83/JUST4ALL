import XCTest
@testable import J4IIndex

/// Conteos para la UI de estado de los rellenos (contenido y vectores).
final class ContentStatsTests: XCTestCase {
    private var tempDir: URL!
    private var index: SearchIndex!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-stats-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        index = SearchIndex(databaseURL: tempDir.appendingPathComponent("index.sqlite"))
    }

    override func tearDownWithError() throws {
        index = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Cuatro ficheros: uno con texto, uno marcado sin texto, uno pendiente (extractor) y uno
    /// sin extractor (no cuenta como pendiente).
    private func seed() async throws -> [String: Int64] {
        let root = tempDir.appendingPathComponent("archivo", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let indexRoot = try await index.addRoot(path: root.path)
        let names = ["nota.txt", "vacio.txt", "pendiente.pdf", "raro.bin"]
        let writes = names.map { name in
            IndexEntryWrite(
                url: root.appendingPathComponent(name),
                isDirectory: false,
                sizeBytes: 16,
                modifiedAt: Date()
            )
        }
        _ = try await index.upsertEntries(rootID: indexRoot.id, writes)

        var ids: [String: Int64] = [:]
        for name in names {
            let maybeID = try await index.entryID(path: root.appendingPathComponent(name).path)
            ids[name] = try XCTUnwrap(maybeID)
        }

        try await index.setDocumentText(entryID: try XCTUnwrap(ids["nota.txt"]), text: "factura de la luz")
        try await index.markContentAttempted(entryID: try XCTUnwrap(ids["vacio.txt"]))
        return ids
    }

    func testContentStatsCountsTextEmptiesAndPending() async throws {
        _ = try await seed()

        let stats = try await index.contentStats(extensions: ["txt", "pdf"])

        XCTAssertEqual(stats.withText, 1, "solo nota.txt tiene texto")
        XCTAssertEqual(stats.attemptedEmpty, 1, "vacio.txt quedó marcado sin texto")
        XCTAssertEqual(stats.pending, 1, "solo pendiente.pdf espera extracción")
    }

    func testContentStatsWithoutExtensionsHasNoPending() async throws {
        _ = try await seed()

        let stats = try await index.contentStats(extensions: [])

        XCTAssertEqual(stats.pending, 0)
        XCTAssertEqual(stats.withText, 1)
    }

    func testSemanticTotalsCountAllAndContentVectors() async throws {
        let ids = try await seed()
        try await index.setEmbedding(entryID: try XCTUnwrap(ids["nota.txt"]), model: "m", source: "content", vector: [1, 0])
        try await index.setEmbedding(entryID: try XCTUnwrap(ids["pendiente.pdf"]), model: "m", source: "name", vector: [0, 1])

        let totals = try await index.semanticTotals()

        XCTAssertEqual(totals.embedded, 2)
        XCTAssertEqual(totals.contentEmbedded, 1)
        XCTAssertEqual(totals.files, 4)
    }
}
