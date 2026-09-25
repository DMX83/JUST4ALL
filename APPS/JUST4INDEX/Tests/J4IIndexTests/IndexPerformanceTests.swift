import XCTest
@testable import J4IIndex

/// Benchmark opt-in (no corre por defecto):
///   J4I_RUN_100K_PERF=1 swift test --filter IndexPerformanceTests
/// Se puede ajustar el tamaño con J4I_PERF_COUNT (por defecto 100000).
final class IndexPerformanceTests: XCTestCase {
    func testCrawlAndQueryPerformance() async throws {
        guard ProcessInfo.processInfo.environment["J4I_RUN_100K_PERF"] == "1" else {
            throw XCTSkip("Definir J4I_RUN_100K_PERF=1 para ejecutar el benchmark.")
        }
        let count = Int(ProcessInfo.processInfo.environment["J4I_PERF_COUNT"] ?? "100000") ?? 100_000
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
            .appendingPathComponent("j4i-perf-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: tempDir) }
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let tree = tempDir.appendingPathComponent("tree", isDirectory: true)
        try fileManager.createDirectory(at: tree, withIntermediateDirectories: true)
        let dirs = max(1, count / 1_000)
        let perDir = max(1, count / dirs)
        for dirIndex in 0..<dirs {
            let dir = tree.appendingPathComponent("dir-\(dirIndex)", isDirectory: true)
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            for fileIndex in 0..<perDir {
                _ = fileManager.createFile(
                    atPath: dir.appendingPathComponent("archivo-\(dirIndex)-\(fileIndex).txt").path,
                    contents: nil
                )
            }
        }

        let index = SearchIndex(databaseURL: tempDir.appendingPathComponent("index.sqlite"))
        let root = try await index.addRoot(path: tree.path)
        let crawler = IndexCrawler(index: index)

        let crawlStart = Date()
        let result = try await crawler.crawl(rootID: root.id, rootPath: tree.path)
        let crawlDuration = Date().timeIntervalSince(crawlStart)
        print("J4I PERF · crawl: \(result.scanned) entradas en \(String(format: "%.2f", crawlDuration)) s")

        try await index.optimize()

        let queries = ["archivo-500", "dir-\(dirs / 2)", "zzzz-no-match", "archivo-\(count / 2)-1", "txt"]
        var totalQueryTime: TimeInterval = 0
        for query in queries {
            let start = Date()
            _ = try await index.search(IndexSearchRequest(query: query, limit: 200))
            let elapsed = Date().timeIntervalSince(start)
            totalQueryTime += elapsed
            print("J4I PERF · query \"\(query)\": \(String(format: "%.1f", elapsed * 1000)) ms")
        }
        print("J4I PERF · query media: \(String(format: "%.1f", totalQueryTime / Double(queries.count) * 1000)) ms")

        XCTAssertLessThan(crawlDuration, 600, "Crawl demasiado lento para 100k")
        XCTAssertLessThan(totalQueryTime / Double(queries.count), 1.0, "Query media demasiado lenta")
    }
}
