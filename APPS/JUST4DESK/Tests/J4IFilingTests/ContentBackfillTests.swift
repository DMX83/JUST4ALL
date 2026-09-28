import XCTest
@testable import J4IFiling
import J4IIndex

/// G7.3 — re-extracción de contenido (candidatos, marcadores de intento, barrido de huérfanos).
final class ContentBackfillTests: XCTestCase {
    private var tempDir: URL!
    private var index: SearchIndex!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-content-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        index = SearchIndex(databaseURL: tempDir.appendingPathComponent("index.sqlite"))
    }

    override func tearDownWithError() throws {
        index = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Raíz con cuatro ficheros: dos con texto, uno vacío y uno sin extractor.
    private func seed() async throws -> [String: Int64] {
        let root = tempDir.appendingPathComponent("archivo", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "Hola, factura de la luz de enero.".write(to: root.appendingPathComponent("nota.txt"), atomically: true, encoding: .utf8)
        try "a,b,c\n1,2,3".write(to: root.appendingPathComponent("datos.csv"), atomically: true, encoding: .utf8)
        try "".write(to: root.appendingPathComponent("vacio.txt"), atomically: true, encoding: .utf8)
        try "sin extractor".write(to: root.appendingPathComponent("raro.bin"), atomically: true, encoding: .utf8)

        let indexRoot = try await index.addRoot(path: root.path)
        let names = ["nota.txt", "datos.csv", "vacio.txt", "raro.bin"]
        let writes = names.map { name in
            IndexEntryWrite(url: root.appendingPathComponent(name), isDirectory: false, sizeBytes: 16, modifiedAt: Date())
        }
        _ = try await index.upsertEntries(rootID: indexRoot.id, writes)

        var ids: [String: Int64] = [:]
        for name in names {
            let maybeID = try await index.entryID(path: root.appendingPathComponent(name).path)
            ids[name] = try XCTUnwrap(maybeID)
        }
        return ids
    }

    func testCandidatesOnlyExtractableWithoutText() async throws {
        _ = try await seed()
        let candidates = try await index.contentCandidates(extensions: ContentBackfill.supportedExtensions, limit: 10)
        XCTAssertEqual(Set(candidates.map(\.name)), ["nota.txt", "datos.csv", "vacio.txt"], "raro.bin no tiene extractor")
    }

    func testRunOnceExtractsAndMarksEmpties() async throws {
        let ids = try await seed()
        let outcome = await ContentBackfill.runOnce(index: index, limit: 10)
        XCTAssertEqual(outcome.extracted, 2)
        XCTAssertEqual(outcome.empty, 1)
        XCTAssertEqual(outcome.processed, 3)

        let noteID = try XCTUnwrap(ids["nota.txt"])
        let text = try await index.documentText(entryID: noteID)
        XCTAssertTrue(text?.contains("factura de la luz") == true)

        let emptyID = try XCTUnwrap(ids["vacio.txt"])
        let emptyText = try await index.documentText(entryID: emptyID)
        XCTAssertEqual(emptyText, "", "el intento sin texto queda marcado")

        let again = try await index.contentCandidates(extensions: ContentBackfill.supportedExtensions, limit: 10)
        XCTAssertTrue(again.isEmpty, "no se reintenta en cada arranque")
    }

    func testEmptyMarkerDoesNotTriggerEmbeddingUpgrade() async throws {
        let ids = try await seed()
        _ = await ContentBackfill.runOnce(index: index, limit: 10)

        let emptyID = try XCTUnwrap(ids["vacio.txt"])
        try await index.setEmbedding(entryID: emptyID, model: "m", source: "name", vector: [1, 0, 0])
        let candidates = try await index.embeddingCandidates(model: "m", limit: 10)
        XCTAssertFalse(candidates.contains { $0.entryID == emptyID }, "un marcador vacío no pide re-vectorizar")

        let noteID = try XCTUnwrap(ids["nota.txt"])
        try await index.setEmbedding(entryID: noteID, model: "m", source: "name", vector: [1, 0, 0])
        let upgrade = try await index.embeddingCandidates(model: "m", limit: 10)
        XCTAssertTrue(upgrade.contains { $0.entryID == noteID }, "un texto real sí pide el vector de contenido")
    }

    func testSweepOrphanContent() async throws {
        _ = try await seed()
        try await index.markContentAttempted(entryID: 999_999)
        let removed = try await index.sweepOrphanContent()
        XCTAssertEqual(removed, 1)
        let second = try await index.sweepOrphanContent()
        XCTAssertEqual(second, 0)
    }
}
