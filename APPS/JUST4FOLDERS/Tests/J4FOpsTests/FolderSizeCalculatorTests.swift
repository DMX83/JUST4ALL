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

    func testComputeSumsSubtreeAndSkipsHiddenWhenAsked() throws {
        let inner = tempDir.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try write(1000, to: tempDir.appendingPathComponent("a.bin"))
        try write(2000, to: inner.appendingPathComponent("b.bin"))
        try write(500, to: inner.appendingPathComponent(".oculto.bin"))

        XCTAssertEqual(
            FolderSizeCalculator.compute(path: tempDir.path, includeHidden: false),
            3000,
            "sin ocultos: 1000 + 2000"
        )
        XCTAssertEqual(
            FolderSizeCalculator.compute(path: tempDir.path, includeHidden: true),
            3500,
            "con ocultos: + 500"
        )
    }

    func testActorCachesAndInvalidates() async throws {
        try write(1234, to: tempDir.appendingPathComponent("c.bin"))
        let calculator = FolderSizeCalculator()

        let first = await calculator.size(of: tempDir, includeHidden: true)
        XCTAssertEqual(first, 1234)
        let cached = await calculator.cachedSize(of: tempDir.standardizedFileURL.path)
        XCTAssertEqual(cached, 1234, "queda en caché tras calcular")

        // Un cambio dentro invalida la carpeta y sus ancestros cacheados.
        try write(100, to: tempDir.appendingPathComponent("d.bin"))
        await calculator.invalidate(path: tempDir.appendingPathComponent("d.bin").path)
        let afterInvalidate = await calculator.cachedSize(of: tempDir.standardizedFileURL.path)
        XCTAssertNil(afterInvalidate, "el ancestro cacheado se invalida")

        let recomputed = await calculator.size(of: tempDir, includeHidden: true)
        XCTAssertEqual(recomputed, 1334, "recalcula con el fichero nuevo")
    }
}
