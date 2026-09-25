import XCTest
@testable import J4IIndex

final class IndexWatchServiceTests: XCTestCase {
    private var tempDir: URL!
    private var index: SearchIndex!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-watch-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        index = SearchIndex(databaseURL: tempDir.appendingPathComponent("index.sqlite"))
    }

    override func tearDownWithError() throws {
        index = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testWatcherPicksUpCreatedAndRemovedFiles() async throws {
        if ProcessInfo.processInfo.environment["J4I_SKIP_FSEVENTS_TESTS"] == "1" {
            throw XCTSkip("Tests de FSEvents deshabilitados por entorno")
        }

        let watchDir = tempDir.appendingPathComponent("watch", isDirectory: true)
        try FileManager.default.createDirectory(at: watchDir, withIntermediateDirectories: true)

        let root = try await index.addRoot(path: watchDir.path)
        let crawler = IndexCrawler(index: index)
        _ = try await crawler.crawl(rootID: root.id, rootPath: watchDir.path)

        let watcher = IndexWatchService(index: index, debounceInterval: 0.4)
        defer { watcher.stopAll() }
        try await watcher.startWatching(rootID: root.id, rootPath: watchDir.path)
        XCTAssertTrue(watcher.isWatching(rootID: root.id))

        // Pequeña espera para que el stream arranque antes de generar cambios.
        try? await Task.sleep(nanoseconds: 500_000_000)

        let created = watchDir.appendingPathComponent("informe-2026.pdf")
        try Data("contenido".utf8).write(to: created)

        let appeared = await waitUntil(timeout: 15) {
            let hits = try await self.index.search(IndexSearchRequest(query: "informe-2026"))
            return hits.count == 1
        }
        XCTAssertTrue(appeared, "FSEvents no indexó el fichero creado a tiempo")

        try FileManager.default.removeItem(at: created)
        let disappeared = await waitUntil(timeout: 15) {
            let hits = try await self.index.search(IndexSearchRequest(query: "informe-2026"))
            return hits.isEmpty
        }
        XCTAssertTrue(disappeared, "FSEvents no eliminó el fichero a tiempo")
    }

    func testWatcherIndexesNewDirectorySubtree() async throws {
        if ProcessInfo.processInfo.environment["J4I_SKIP_FSEVENTS_TESTS"] == "1" {
            throw XCTSkip("Tests de FSEvents deshabilitados por entorno")
        }

        let watchDir = tempDir.appendingPathComponent("watch2", isDirectory: true)
        try FileManager.default.createDirectory(at: watchDir, withIntermediateDirectories: true)

        let root = try await index.addRoot(path: watchDir.path)
        let crawler = IndexCrawler(index: index)
        _ = try await crawler.crawl(rootID: root.id, rootPath: watchDir.path)

        let watcher = IndexWatchService(index: index, debounceInterval: 0.4)
        defer { watcher.stopAll() }
        try await watcher.startWatching(rootID: root.id, rootPath: watchDir.path)
        try? await Task.sleep(nanoseconds: 500_000_000)

        let folder = watchDir.appendingPathComponent("lote-nuevo", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("uno".utf8).write(to: folder.appendingPathComponent("documento-uno.txt"))
        try Data("dos".utf8).write(to: folder.appendingPathComponent("documento-dos.txt"))

        let indexed = await waitUntil(timeout: 15) {
            let hits = try await self.index.search(IndexSearchRequest(query: "documento-uno"))
            let hits2 = try await self.index.search(IndexSearchRequest(query: "documento-dos"))
            return hits.count == 1 && hits2.count == 1
        }
        XCTAssertTrue(indexed, "FSEvents no indexó el subárbol nuevo a tiempo")
    }

    // MARK: - Helpers

    private func waitUntil(timeout: TimeInterval, _ condition: () async throws -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (try? await condition()) == true { return true }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return (try? await condition()) == true
    }
}
