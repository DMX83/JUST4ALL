import XCTest
@testable import J4IIndex

/// G7.4 — reindexado conservador: los textos y vectores sobreviven y se re-vinculan por ruta.
final class ReindexPreservationTests: XCTestCase {
    private var tempDir: URL!
    private var index: SearchIndex!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-reindex-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        index = SearchIndex(databaseURL: tempDir.appendingPathComponent("index.sqlite"))
    }

    override func tearDownWithError() throws {
        index = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func seedRoot() async throws -> (root: URL, rootID: Int64, notePath: String) {
        let root = tempDir.appendingPathComponent("archivo", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let noteURL = root.appendingPathComponent("nota.txt")
        try "texto".write(to: noteURL, atomically: true, encoding: .utf8)
        let indexRoot = try await index.addRoot(path: root.path)
        _ = try await index.upsertEntries(rootID: indexRoot.id, [
            IndexEntryWrite(url: noteURL, isDirectory: false, sizeBytes: 5, modifiedAt: Date())
        ])
        return (root, indexRoot.id, noteURL.path)
    }

    func testPreserveRestoreRoundTrip() async throws {
        let (_, rootID, notePath) = try await seedRoot()
        let maybeOld = try await index.entryID(path: notePath)
        let oldID = try XCTUnwrap(maybeOld)
        try await index.setDocumentText(entryID: oldID, text: "contenido importante")
        try await index.setEmbedding(entryID: oldID, model: "m", source: "content", vector: [1, 2, 3])

        try await index.preserveContentSnapshot(rootID: rootID)
        try await index.clearEntries(rootID: rootID)
        _ = try await index.upsertEntries(rootID: rootID, [
            IndexEntryWrite(path: notePath, isDirectory: false, sizeBytes: 5, modifiedAt: Date())
        ])
        let restored = try await index.restorePreservedContent(rootID: rootID)
        XCTAssertEqual(restored, 1)

        let maybeNew = try await index.entryID(path: notePath)
        let newID = try XCTUnwrap(maybeNew)
        XCTAssertNotEqual(newID, oldID, "el reindexado recrea la entrada con otro id")
        let text = try await index.documentText(entryID: newID)
        XCTAssertEqual(text, "contenido importante")
        let stats = try await index.embeddingStats(model: "m")
        XCTAssertEqual(stats.embedded, 1)
    }

    func testCrawlerReindexKeepsTextByPath() async throws {
        let (root, rootID, notePath) = try await seedRoot()
        let maybeOld = try await index.entryID(path: notePath)
        let oldID = try XCTUnwrap(maybeOld)
        try await index.setDocumentText(entryID: oldID, text: "sobrevive al reindexado")

        let crawler = IndexCrawler(index: index)
        _ = try await crawler.reindex(rootID: rootID, rootPath: root.path)

        let maybeNew = try await index.entryID(path: notePath)
        let newID = try XCTUnwrap(maybeNew)
        let text = try await index.documentText(entryID: newID)
        XCTAssertEqual(text, "sobrevive al reindexado")

        let candidates = try await index.contentCandidates(extensions: ["txt"], limit: 10)
        XCTAssertFalse(candidates.contains { $0.entryID == newID }, "ya no hay que re-extraer el texto")
    }

    func testPreserveWithoutContentIsHarmless() async throws {
        let (_, rootID, notePath) = try await seedRoot()
        try await index.preserveContentSnapshot(rootID: rootID)
        try await index.clearEntries(rootID: rootID)
        _ = try await index.upsertEntries(rootID: rootID, [
            IndexEntryWrite(path: notePath, isDirectory: false, sizeBytes: 5, modifiedAt: Date())
        ])
        let restored = try await index.restorePreservedContent(rootID: rootID)
        XCTAssertEqual(restored, 0)
    }
}
