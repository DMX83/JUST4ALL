import XCTest
@testable import J4IIndex

/// Higiene de vectores (N7): los embeddings de entradas que ya no existen se barren.
final class EmbeddingSweepTests: XCTestCase {
    func testSweepRemovesOrphanVectors() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-sweep-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let index = SearchIndex(databaseURL: tempDir.appendingPathComponent("index.sqlite"))

        // Vector de una entrada inexistente (así quedaron los del incidente del reindexado).
        try await index.setEmbedding(entryID: 999_999, model: "test-model", source: "name", vector: [1, 0, 0])
        var stats = try await index.embeddingStats(model: "test-model")
        XCTAssertEqual(stats.embedded, 1)

        let swept = try await index.sweepOrphanEmbeddings()
        XCTAssertEqual(swept, 1, "el vector huérfano debe barrerse")

        stats = try await index.embeddingStats(model: "test-model")
        XCTAssertEqual(stats.embedded, 0)

        let secondSweep = try await index.sweepOrphanEmbeddings()
        XCTAssertEqual(secondSweep, 0, "segundo barrido: nada que limpiar")
    }
}
