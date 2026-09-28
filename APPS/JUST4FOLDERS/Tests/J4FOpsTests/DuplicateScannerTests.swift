import XCTest
@testable import J4FOps

final class DuplicateScannerTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4f-dup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func write(_ name: String, bytes: Int, fill: UInt8) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try Data(repeating: fill, count: bytes).write(to: url)
        return url
    }

    func testFindsGroupsByHashAndSize() async throws {
        _ = try write("a1.bin", bytes: 2048, fill: 0xAA)
        _ = try write("a2.bin", bytes: 2048, fill: 0xAA)
        _ = try write("b1.bin", bytes: 1024, fill: 0xBB)
        _ = try write("b2.bin", bytes: 1024, fill: 0xBB)
        _ = try write("unico.bin", bytes: 2048, fill: 0xCC)

        let groups = try await DuplicateScanner.find(in: tempDir)
        XCTAssertEqual(groups.count, 2, "dos grupos: 2×2048 y 2×1024")

        let big = groups.first { $0.sizeBytes == 2048 }
        XCTAssertEqual(big?.files.count, 2)
        XCTAssertEqual(big?.wastedBytes, 2048, "conservando una copia se recuperan 2 KB")
        XCTAssertEqual(big?.files.map { $0.lastPathComponent }, ["a1.bin", "a2.bin"])
    }

    func testSameSizeDifferentContentIsNotGrouped() async throws {
        _ = try write("x1.bin", bytes: 1024, fill: 0x01)
        _ = try write("x2.bin", bytes: 1024, fill: 0x02)
        let groups = try await DuplicateScanner.find(in: tempDir)
        XCTAssertTrue(groups.isEmpty, "mismo tamaño ≠ duplicado")
    }

    func testMinSizeAndEmptyFiles() async throws {
        _ = try write("e1.bin", bytes: 0, fill: 0)
        _ = try write("e2.bin", bytes: 0, fill: 0)
        _ = try write("m1.bin", bytes: 100, fill: 0x07)
        _ = try write("m2.bin", bytes: 100, fill: 0x07)

        let all = try await DuplicateScanner.find(in: tempDir)
        XCTAssertEqual(all.count, 1, "los vacíos se ignoran (minSize 1)")
        XCTAssertEqual(all.first?.sizeBytes, 100)

        let none = try await DuplicateScanner.find(in: tempDir, minSize: 10_000)
        XCTAssertTrue(none.isEmpty)
    }
}
