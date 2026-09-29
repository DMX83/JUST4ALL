import XCTest
@testable import J4FOps

final class FolderSizeCalculatorTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4f-folder-size-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func write(_ bytes: Int, to url: URL) throws {
        try Data(repeating: 0x41, count: bytes).write(to: url)
    }

    /// v2.3.10 — el calculo suma el tamano ASIGNADO en disco (bloques), no el logico.
    private func allocatedSize(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
    }

    func testComputeSumsSubtreeAndSkipsHiddenWhenAsked() throws {
        let inner = tempDir.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        let a = tempDir.appendingPathComponent("a.bin")
        let b = inner.appendingPathComponent("b.bin")
        let oculto = inner.appendingPathComponent(".oculto.bin")
        try write(1000, to: a)
        try write(2000, to: b)
        try write(500, to: oculto)

        XCTAssertEqual(
            FolderSizeCalculator.compute(path: tempDir.path, includeHidden: false),
            allocatedSize(of: a) + allocatedSize(of: b),
            "sin ocultos: a + b (tamano asignado en disco)"
        )
        XCTAssertEqual(
            FolderSizeCalculator.compute(path: tempDir.path, includeHidden: true),
            allocatedSize(of: a) + allocatedSize(of: b) + allocatedSize(of: oculto),
            "con ocultos: + .oculto.bin"
        )
    }

    /// v2.3.10 — regresion del fallo de ~/Library: un fichero DISPERSO (Docker.raw: 995 GB
    /// logicos / 71 GB reales) hacia que una carpeta mostrara mas tamano del que existe en disco.
    func testSparseFileCountsAllocatedNotLogical() throws {
        let sparse = tempDir.appendingPathComponent("sparse.bin")
        try write(4096, to: sparse)
        let handle = try FileHandle(forWritingTo: sparse)
        try handle.truncate(atOffset: 5 * 1024 * 1024 * 1024)
        try handle.close()

        let logical = try XCTUnwrap(try sparse.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        XCTAssertEqual(logical, 5 * 1024 * 1024 * 1024, "el fichero es disperso: 5 GB logicos")
        let computed = FolderSizeCalculator.compute(path: tempDir.path, includeHidden: true)
        XCTAssertLessThan(computed, 100_000_000, "cuenta lo asignado (unos KB), no los 5 GB logicos")
        XCTAssertEqual(computed, allocatedSize(of: sparse))
    }

    func testDiskCacheAvoidsRepeatedWalk() async throws {
        let storeURL = tempDir.appendingPathComponent("sizes.json")
        let store = FolderSizeCacheStore(ttl: 3600, capacity: 64, fileURL: storeURL)
        let dir = tempDir.appendingPathComponent("cacheable", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("x.bin")
        try write(4096, to: file)

        let calculator = FolderSizeCalculator(cacheStore: store)
        let first = await calculator.size(of: dir, includeHidden: true)
        XCTAssertEqual(first, allocatedSize(of: file))

        // v2.3.11 — vaciamos la carpeta: un recorrido daría 0. Si sigue devolviendo el valor, viene
        // de la caché en disco (objetivo: no repetir los ~19 s de recorrido de `~/Library`).
        try FileManager.default.removeItem(at: file)
        let fresh = FolderSizeCalculator(cacheStore: store)
        let second = await fresh.size(of: dir, includeHidden: true)
        XCTAssertEqual(second, first, "segundo arranque: se reutiliza la caché, sin recorrer")

        // Tras invalidar (lo que hace el watcher al detectar cambios), sí se recalcula.
        _ = await fresh.refreshSize(of: dir, includeHidden: true)
        let third = await fresh.size(of: dir, includeHidden: true)
        XCTAssertEqual(third, 0, "tras invalidar se recalcula de verdad (carpeta vacía)")
    }

    func testDiskCacheExpiresWithTTL() throws {
        let storeURL = tempDir.appendingPathComponent("sizes-ttl.json")
        let old = Date().timeIntervalSince1970 - 7200
        let json = "{\"/tmp/algo\": {\"bytes\": 123, \"timestamp\": \(old)}}"
        try Data(json.utf8).write(to: storeURL)

        let store = FolderSizeCacheStore(ttl: 3600, capacity: 64, fileURL: storeURL)
        XCTAssertNil(store.value(for: "/tmp/algo"), "caducado: hay que volver a recorrer")

        store.store(456, for: "/tmp/algo")
        store.flush()
        let reopened = FolderSizeCacheStore(ttl: 3600, capacity: 64, fileURL: storeURL)
        XCTAssertEqual(reopened.value(for: "/tmp/algo"), 456, "persiste entre instancias")
    }

    func testActorCachesAndInvalidates() async throws {
        let c = tempDir.appendingPathComponent("c.bin")
        try write(1234, to: c)
        let calculator = FolderSizeCalculator()
        let expected = allocatedSize(of: c)

        let first = await calculator.size(of: tempDir, includeHidden: true)
        XCTAssertEqual(first, expected)
        let cached = await calculator.cachedSize(of: tempDir.standardizedFileURL.path)
        XCTAssertEqual(cached, expected, "queda en caché tras calcular")

        // Un cambio dentro invalida la carpeta y sus ancestros cacheados.
        let d = tempDir.appendingPathComponent("d.bin")
        try write(100, to: d)
        await calculator.invalidate(path: d.path)
        let afterInvalidate = await calculator.cachedSize(of: tempDir.standardizedFileURL.path)
        XCTAssertNil(afterInvalidate, "el ancestro cacheado se invalida")

        let recomputed = await calculator.size(of: tempDir, includeHidden: true)
        XCTAssertEqual(recomputed, expected + allocatedSize(of: d), "recalcula con el fichero nuevo")
    }
}
