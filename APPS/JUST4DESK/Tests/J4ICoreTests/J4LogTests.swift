import XCTest
@testable import J4ICore

final class J4LogTests: XCTestCase {
    func testBufferRetainsOrderAndRespectsCapacity() {
        let core = J4LogCore(capacity: 3, fileURL: nil, usesOSLog: false)
        core.log(.info, .app, "uno")
        core.log(.info, .app, "dos")
        core.log(.info, .app, "tres")
        core.log(.info, .app, "cuatro")

        let entries = core.entries(limit: 10)
        XCTAssertEqual(entries.map(\.message), ["dos", "tres", "cuatro"])
        XCTAssertEqual(entries.map(\.id), [2, 3, 4])
    }

    func testLevelsAreComparable() {
        XCTAssertTrue(J4LogLevel.debug < .info)
        XCTAssertTrue(J4LogLevel.info < .warning)
        XCTAssertTrue(J4LogLevel.warning < .error)
        XCTAssertFalse(J4LogLevel.error < .debug)
    }

    func testCategoryDisplayNames() {
        XCTAssertEqual(J4LogCategory.ai.displayName, "IA")
        XCTAssertEqual(J4LogCategory.filing.displayName, "Archivado")
        XCTAssertEqual(J4LogCategory.ingest.displayName, "Ingesta")
    }

    func testSourceContainsFileAndLine() {
        let core = J4LogCore(capacity: 10, fileURL: nil, usesOSLog: false)
        core.log(.info, .search, "hola", file: "J4ICore/SearchIndex.swift", line: 42)
        XCTAssertEqual(core.entries(limit: 1).first?.source, "SearchIndex.swift:42")
    }

    func testStreamReceivesLiveEntries() async {
        let core = J4LogCore(capacity: 10, fileURL: nil, usesOSLog: false)
        var iterator = core.stream().makeAsyncIterator()

        core.log(.info, .search, "primera")
        let first = await iterator.next()
        XCTAssertEqual(first?.message, "primera")
        XCTAssertEqual(first?.level, J4LogLevel.info)

        core.log(.error, .ai, "fallo")
        let second = await iterator.next()
        XCTAssertEqual(second?.level, J4LogLevel.error)
        XCTAssertEqual(second?.message, "fallo")
    }

    func testClearBufferEmptiesHistory() {
        let core = J4LogCore(capacity: 10, fileURL: nil, usesOSLog: false)
        core.log(.info, .app, "algo")
        core.clearBuffer()
        XCTAssertTrue(core.entries(limit: 10).isEmpty)
    }

    func testWritesFileLines() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4log-tests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("test.log", isDirectory: false)
        let core = J4LogCore(capacity: 10, fileURL: fileURL, usesOSLog: false)

        core.log(.warning, .filing, "cuarentena de prueba")
        core.log(.info, .index, "indexación de prueba")

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("[AVISO] [filing] cuarentena de prueba"), contents)
        XCTAssertTrue(contents.contains("[INFO] [index] indexación de prueba"), contents)
        XCTAssertTrue(contents.contains("J4LogTests.swift"), contents)

        try? FileManager.default.removeItem(at: directory)
    }
}
