import XCTest
@testable import J4IIndex

/// G7 — almacén de embeddings locales, candidatos, ranking y fusión semántica.
final class SemanticIndexTests: XCTestCase {
    private var tempDir: URL!
    private var index: SearchIndex!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-semantic-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        index = SearchIndex(databaseURL: tempDir.appendingPathComponent("index.sqlite"))
    }

    override func tearDownWithError() throws {
        index = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Siembra un root con tres ficheros y devuelve (rootID, paths).
    private func seed() async throws -> (Int64, [String]) {
        let rootDir = tempDir.appendingPathComponent("archivo", isDirectory: true)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        let root = try await index.addRoot(path: rootDir.path)
        let paths = ["factura-luz.pdf", "nomina-mayo.pdf", "foto-playa.jpg"].map {
            rootDir.appendingPathComponent($0).path
        }
        let writes = paths.enumerated().map { offset, path in
            IndexEntryWrite(path: path, isDirectory: false, sizeBytes: Int64(100 * (offset + 1)), modifiedAt: Date())
        }
        _ = try await index.upsertEntries(rootID: root.id, writes)
        return (root.id, paths)
    }

    func testFloatPackingRoundTrip() {
        let floats: [Float] = [0.5, -1.25, 3.75, 0]
        let data = SearchIndex.packFloats(floats)
        XCTAssertEqual(data.count, 16)
        XCTAssertEqual(SearchIndex.unpackFloats(data, count: 4), floats)
        XCTAssertNil(SearchIndex.unpackFloats(data, count: 3))
    }

    func testEmbeddingRoundTripAndStats() async throws {
        let (_, paths) = try await seed()
        let id = try await index.entryID(path: paths[0])
        let entryID = try XCTUnwrap(id)

        var stats = try await index.embeddingStats(model: "test-model")
        XCTAssertEqual(stats.embedded, 0)
        XCTAssertEqual(stats.files, 3)

        try await index.setEmbedding(entryID: entryID, model: "test-model", source: "name", vector: [1, 0, 0])
        stats = try await index.embeddingStats(model: "test-model")
        XCTAssertEqual(stats.embedded, 1)
        XCTAssertEqual(stats.files, 3)

        // Otro modelo no cuenta como vectorizado.
        stats = try await index.embeddingStats(model: "otro-modelo")
        XCTAssertEqual(stats.embedded, 0)
    }

    func testEmbeddingCandidatesPrioritizeMissingAndContentUpgrade() async throws {
        let (_, paths) = try await seed()
        let maybeFirst = try await index.entryID(path: paths[0])
        let first = try XCTUnwrap(maybeFirst)

        var candidates = try await index.embeddingCandidates(model: "m", limit: 10)
        XCTAssertEqual(candidates.count, 3, "sin vectores, los tres ficheros son candidatos")

        try await index.setEmbedding(entryID: first, model: "m", source: "name", vector: [1, 0, 0])
        candidates = try await index.embeddingCandidates(model: "m", limit: 10)
        XCTAssertEqual(candidates.count, 2)

        // Llega el texto del documento: el vector por nombre se queda corto y vuelve a ser candidato.
        try await index.setDocumentText(entryID: first, text: "Factura de la luz de enero. Importe 84,32 euros.")
        candidates = try await index.embeddingCandidates(model: "m", limit: 10)
        XCTAssertEqual(candidates.count, 3)
        XCTAssertTrue(candidates.contains { $0.entryID == first && $0.documentText != nil })

        // Re-vectorizado con el texto queda al día.
        try await index.setEmbedding(entryID: first, model: "m", source: "content", vector: [1, 0, 0])
        candidates = try await index.embeddingCandidates(model: "m", limit: 10)
        XCTAssertEqual(candidates.count, 2)
    }

    func testSemanticHitsRankAndApplyFilters() async throws {
        let (_, paths) = try await seed()
        var ids: [Int64] = []
        for path in paths {
            let maybeID = try await index.entryID(path: path)
            ids.append(try XCTUnwrap(maybeID))
        }
        try await index.setEmbedding(entryID: ids[0], model: "m", source: "name", vector: [1, 0, 0])
        try await index.setEmbedding(entryID: ids[1], model: "m", source: "name", vector: [0, 1, 0])
        try await index.setEmbedding(entryID: ids[2], model: "m", source: "name", vector: [0, 0, 1])

        let hits = try await index.semanticHits(queryVector: [1, 0, 0], model: "m", limit: 3)
        XCTAssertEqual(hits.count, 3)
        XCTAssertEqual(hits.first?.entry.id, ids[0])
        XCTAssertEqual(hits.first?.score ?? 0, 1.0, accuracy: 0.0001)
        XCTAssertTrue(hits.allSatisfy(\.matchedSemantically))

        var filters = IndexSearchFilters()
        filters.extensions = ["pdf"]
        let pdfHits = try await index.semanticHits(queryVector: [0, 1, 0], model: "m", limit: 3, filters: filters)
        XCTAssertEqual(pdfHits.count, 2)
        XCTAssertTrue(pdfHits.allSatisfy { $0.entry.ext == "pdf" })

        let contentOnly = try await index.semanticHits(queryVector: [1, 0, 0], model: "m", limit: 3, contentOnly: true)
        XCTAssertTrue(contentOnly.isEmpty, "solo puntúan los vectores construidos con texto de documento")

        let none = try await index.semanticHits(queryVector: [1, 0], model: "m", limit: 3)
        XCTAssertTrue(none.isEmpty, "una dimensión distinta no puntúa")
    }

    func testUpsertCarriesDocumentTextAndEmbedding() async throws {
        let (rootID, paths) = try await seed()
        let maybeFirst = try await index.entryID(path: paths[0])
        let first = try XCTUnwrap(maybeFirst)
        try await index.setDocumentText(entryID: first, text: "Factura de la luz de enero.")
        try await index.setEmbedding(entryID: first, model: "m", source: "content", vector: [1, 0, 0])

        // Reindexar la misma ruta recrea la entrada (id nuevo) y debe conservar texto y vector.
        let write = IndexEntryWrite(path: paths[0], isDirectory: false, sizeBytes: 999, modifiedAt: Date())
        _ = try await index.upsertEntries(rootID: rootID, [write])

        let maybeNew = try await index.entryID(path: paths[0])
        let newID = try XCTUnwrap(maybeNew)
        XCTAssertNotEqual(newID, first, "el upsert re-crea la entrada con otro id")

        let text = try await index.documentText(entryID: newID)
        XCTAssertEqual(text, "Factura de la luz de enero.")

        let candidates = try await index.embeddingCandidates(model: "m", limit: 10)
        XCTAssertFalse(candidates.contains { $0.entryID == newID }, "el vector viajó a la entrada nueva")

        let stats = try await index.embeddingStats(model: "m")
        XCTAssertEqual(stats.embedded, 1, "sin filas huérfanas duplicadas")
    }

    func testSemanticMergeKeepsKeywordFirstAndDeduplicates() {
        let rootID: Int64 = 1
        func hit(_ id: Int64, score: Double) -> IndexSearchHit {
            IndexSearchHit(
                entry: IndexEntry(id: id, rootID: rootID, path: "/tmp/f\(id).pdf", name: "f\(id).pdf", ext: "pdf", isDirectory: false, sizeBytes: 1, modifiedAt: nil),
                score: score,
                matchedContent: false,
                contentSnippet: nil
            )
        }
        let keyword = [hit(1, score: 0.1), hit(2, score: 0.2)]
        let semantic = [hit(3, score: 0.9), hit(2, score: 0.8), hit(4, score: 0.7)]

        let merged = SemanticMerge.merge(keyword: keyword, semantic: semantic, semanticLimit: 2, totalLimit: 50)
        XCTAssertEqual(merged.map(\.entry.id), [1, 2, 3, 4])
        XCTAssertFalse(merged[0].matchedSemantically)
        XCTAssertTrue(merged[2].matchedSemantically)
        XCTAssertTrue(merged[3].matchedSemantically)
    }

    func testEmbedderSeparatesRelatedSentencesWhenAvailable() async throws {
        guard let embedder = DocEmbedder.make() else {
            throw XCTSkip("Sin embeddings del sistema en este Mac.")
        }
        guard let a = await embedder.embedNormalized("factura de la luz de enero"),
              let b = await embedder.embedNormalized("recibo de electricidad de la companía"),
              let c = await embedder.embedNormalized("foto de la playa en verano") else {
            throw XCTSkip("El embedder no devolvió vectores.")
        }
        let related = DocEmbedder.cosineSimilarity(a, b)
        let unrelated = DocEmbedder.cosineSimilarity(a, c)
        XCTAssertGreaterThan(related, unrelated + 0.02, "«factura/recibo» debe parecerse más que «factura/playa»")
        XCTAssertEqual(a.count, embedder.dimension)
    }
}
