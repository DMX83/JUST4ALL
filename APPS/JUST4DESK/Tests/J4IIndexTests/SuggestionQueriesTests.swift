import XCTest
@testable import J4IIndex

/// G2 — consultas del índice para los detectores de sugerencias: tamaños distintos (candidatos
/// baratos a duplicado) y ficheros grandes/olvidados.
final class SuggestionQueriesTests: XCTestCase {
    private var tempDir: URL!
    private var index: SearchIndex!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-suggestion-queries-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        index = SearchIndex(databaseURL: tempDir.appendingPathComponent("index.sqlite"))
    }

    override func tearDownWithError() throws {
        index = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func entry(_ path: String, size: Int64, modifiedAt: Date? = Date(timeIntervalSince1970: 1_700_000_000), isDirectory: Bool = false) -> IndexEntryWrite {
        IndexEntryWrite(path: path, isDirectory: isDirectory, sizeBytes: size, modifiedAt: modifiedAt)
    }

    func testIndexedFileSizesAreDistinctAndFiltered() async throws {
        let root = tempDir.appendingPathComponent("root", isDirectory: true).path
        let rootEntry = try await index.addRoot(path: root)
        try await index.upsertEntries(rootID: rootEntry.id, [
            entry("\(root)/a.pdf", size: 2_000_000),
            entry("\(root)/b.pdf", size: 2_000_000),
            entry("\(root)/c.bin", size: 500),
            entry("\(root)/Carpeta", size: 4096, isDirectory: true)
        ])

        let sizes = try await index.indexedFileSizes(minBytes: 1_000)
        XCTAssertEqual(sizes, [2_000_000], "tamaños distintos, sin directorios ni downs pequeños")
    }

    func testLargeFilesFilterByAgeAndOrderBySize() async throws {
        let root = tempDir.appendingPathComponent("root2", isDirectory: true).path
        let rootEntry = try await index.addRoot(path: root)
        let old = Date(timeIntervalSince1970: 1_400_000_000)
        let recent = Date()
        try await index.upsertEntries(rootID: rootEntry.id, [
            entry("\(root)/grande-viejo.iso", size: 3_000_000_000, modifiedAt: old),
            entry("\(root)/grande-nuevo.iso", size: 2_000_000_000, modifiedAt: recent),
            entry("\(root)/mediano-viejo.bin", size: 10, modifiedAt: old)
        ])

        let cutoff = Date(timeIntervalSince1970: 1_600_000_000)
        let forgotten = try await index.largeFiles(minBytes: 1_000_000_000, olderThan: cutoff, limit: 10)
        XCTAssertEqual(forgotten.map(\.name), ["grande-viejo.iso"], "solo ≥1 GB y sin cambios desde el corte")

        let all = try await index.largeFiles(minBytes: 1_000_000_000, olderThan: nil, limit: 1)
        XCTAssertEqual(all.count, 1, "respeta el límite")
        XCTAssertEqual(all.first?.name, "grande-viejo.iso", "orden por tamaño descendente")
    }
}
