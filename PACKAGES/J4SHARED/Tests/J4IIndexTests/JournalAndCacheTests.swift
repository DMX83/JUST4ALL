import XCTest
@testable import J4IIndex

final class JournalAndCacheTests: XCTestCase {
    private var tempDir: URL!
    private var index: SearchIndex!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-journal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        index = SearchIndex(databaseURL: tempDir.appendingPathComponent("index.sqlite"))
    }

    override func tearDownWithError() throws {
        index = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testCacheRoundTripAndFiledPathPreserved() async throws {
        try await index.storeCachedAnalysis(hash: "abc", profileJSON: "{\"a\":1}", proposalJSON: "{\"b\":2}")
        let cached = try await index.loadCachedAnalysis(hash: "abc")
        XCTAssertEqual(cached?.profileJSON, "{\"a\":1}")
        XCTAssertEqual(cached?.proposalJSON, "{\"b\":2}")
        XCTAssertNil(cached?.filedPath)

        try await index.updateCachedFiledPath(hash: "abc", filedPath: "/tmp/x.pdf")
        let withFiled = try await index.loadCachedAnalysis(hash: "abc")
        XCTAssertEqual(withFiled?.filedPath, "/tmp/x.pdf")

        try await index.storeCachedAnalysis(hash: "abc", profileJSON: "{\"a\":3}", proposalJSON: nil)
        let updated = try await index.loadCachedAnalysis(hash: "abc")
        XCTAssertEqual(updated?.profileJSON, "{\"a\":3}")
        XCTAssertEqual(updated?.proposalJSON, "{\"b\":2}", "el proposal previo se conserva si el nuevo es nil")
        XCTAssertEqual(updated?.filedPath, "/tmp/x.pdf", "el filed_path previo se conserva")
    }

    func testJournalAppendAndUndo() async throws {
        let id = try await index.journalAppend(
            batchID: "b1",
            sourcePath: "/s/a.pdf",
            destinationPath: "/d/a.pdf",
            categoryPath: "01_Fiscal/Facturas",
            action: "move"
        )
        let entries = try await index.journalRecent()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.id, id)
        XCTAssertTrue(entries.first?.isUndoable == true)
        let batch = try await index.journalLatestBatchID()
        XCTAssertEqual(batch, "b1")

        try await index.journalMarkUndone(id: id)
        let updated = try await index.journalEntry(id: id)
        XCTAssertEqual(updated?.state, "undone")
        XCTAssertFalse(updated?.isUndoable == true)
        XCTAssertNotNil(updated?.undoneAt)
    }

    func testEntryIDAndRootContaining() async throws {
        let rootPath = tempDir.appendingPathComponent("rootA", isDirectory: true).path
        let root = try await index.addRoot(path: rootPath)
        let filePath = "\(rootPath)/01_Fiscal/Facturas/factura.pdf"
        try await index.upsertEntries(rootID: root.id, [
            IndexEntryWrite(path: filePath, isDirectory: false, sizeBytes: 10, modifiedAt: Date())
        ])

        let entryID = try await index.entryID(path: filePath)
        XCTAssertNotNil(entryID)

        let containing = try await index.rootID(containing: filePath)
        XCTAssertEqual(containing?.id, root.id)
        let missing = try await index.rootID(containing: "/otra/ruta/x.pdf")
        XCTAssertNil(missing)
    }
}
