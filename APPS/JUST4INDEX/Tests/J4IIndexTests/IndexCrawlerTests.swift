import XCTest
@testable import J4IIndex

final class IndexCrawlerTests: XCTestCase {
    private var tempDir: URL!
    private var index: SearchIndex!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-crawler-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        index = SearchIndex(databaseURL: tempDir.appendingPathComponent("index.sqlite"))
    }

    override func tearDownWithError() throws {
        index = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Helpers

    private func makeTree() throws -> URL {
        let fileManager = FileManager.default
        let tree = tempDir.appendingPathComponent("tree", isDirectory: true)
        try fileManager.createDirectory(at: tree.appendingPathComponent("docs"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: tree.appendingPathComponent("fotos"), withIntermediateDirectories: true)
        try Data("hola".utf8).write(to: tree.appendingPathComponent("nota.txt"))
        try Data("pdf".utf8).write(to: tree.appendingPathComponent("docs/carta.pdf"))
        try Data("img".utf8).write(to: tree.appendingPathComponent("fotos/vacaciones.jpg"))
        try Data("oculto".utf8).write(to: tree.appendingPathComponent(".secreto.txt"))
        return tree
    }

    // MARK: - Tests

    func testCrawlIndexesTreeAndSkipsHidden() async throws {
        let tree = try makeTree()
        let root = try await index.addRoot(path: tree.path)
        let crawler = IndexCrawler(index: index)

        let result = try await crawler.crawl(rootID: root.id, rootPath: tree.path)
        XCTAssertGreaterThanOrEqual(result.scanned, 6)

        let status = try await index.rootStatus(id: root.id)
        XCTAssertEqual(status.state, .ready)
        XCTAssertEqual(status.entryCount, result.scanned)
        XCTAssertEqual(status.scannedCount, result.scanned)

        let carta = try await index.search(IndexSearchRequest(query: "carta"))
        XCTAssertEqual(carta.count, 1)
        XCTAssertFalse(carta[0].entry.isDirectory)

        let docs = try await index.search(IndexSearchRequest(query: "docs"))
        XCTAssertTrue(docs.contains { $0.entry.isDirectory })

        let hidden = try await index.search(IndexSearchRequest(query: "secreto"))
        XCTAssertTrue(hidden.isEmpty, "los ocultos se saltan por defecto")
    }

    func testCrawlIncludeHidden() async throws {
        let tree = try makeTree()
        let root = try await index.addRoot(path: tree.path)
        let crawler = IndexCrawler(index: index)

        _ = try await crawler.crawl(
            rootID: root.id,
            rootPath: tree.path,
            options: CrawlOptions(includeHidden: true)
        )
        let hidden = try await index.search(IndexSearchRequest(query: "secreto"))
        XCTAssertEqual(hidden.count, 1)
    }

    func testReindexReflectsNewFilesWithoutDuplicates() async throws {
        let tree = try makeTree()
        let root = try await index.addRoot(path: tree.path)
        let crawler = IndexCrawler(index: index)
        _ = try await crawler.crawl(rootID: root.id, rootPath: tree.path)

        try Data("nuevo".utf8).write(to: tree.appendingPathComponent("nuevo.txt"))
        let result = try await crawler.reindex(rootID: root.id, rootPath: tree.path)

        let nuevo = try await index.search(IndexSearchRequest(query: "nuevo"))
        XCTAssertEqual(nuevo.count, 1)
        let carta = try await index.search(IndexSearchRequest(query: "carta"))
        XCTAssertEqual(carta.count, 1)
        let status = try await index.rootStatus(id: root.id)
        XCTAssertEqual(status.entryCount, result.scanned)
    }

    func testCrawlCancellationLeavesRootPending() async throws {
        let fileManager = FileManager.default
        let big = tempDir.appendingPathComponent("big", isDirectory: true)
        try fileManager.createDirectory(at: big, withIntermediateDirectories: true)
        for indexValue in 0..<30 {
            try Data().write(to: big.appendingPathComponent("f\(indexValue).txt"))
        }

        let root = try await index.addRoot(path: big.path)
        let crawler = IndexCrawler(index: index)
        var checks = 0

        do {
            _ = try await crawler.crawl(
                rootID: root.id,
                rootPath: big.path,
                options: CrawlOptions(batchSize: 5),
                shouldCancel: {
                    checks += 1
                    return checks > 12
                }
            )
            XCTFail("Se esperaba cancelación")
        } catch is CancellationError {
            // esperado
        }

        let midStatus = try await index.rootStatus(id: root.id)
        XCTAssertEqual(midStatus.state, .pending)
        XCTAssertLessThan(midStatus.entryCount, 31)

        _ = try await crawler.crawl(rootID: root.id, rootPath: big.path)
        let finalStatus = try await index.rootStatus(id: root.id)
        XCTAssertEqual(finalStatus.state, .ready)
        XCTAssertEqual(finalStatus.entryCount, 31, "root + 30 ficheros, sin duplicados")
    }
}
